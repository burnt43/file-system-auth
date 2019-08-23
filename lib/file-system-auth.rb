require 'pathname'
require 'fileutils'

module FileSystemAuth
  PermissionOptions = Struct.new(:chmod_octal, :user, :group) do
    def to_s
      "<#{self.class.name} chmod_octal=#{chmod_octal&.to_s(8)} user=#{user} group=#{group}>"
    end

    def processed_user
      if user.is_a?(Proc)
        user.call
      else
        user
      end
    end

    def processed_group
      if group.is_a?(Proc)
        group.call
      else
        group
      end
    end
  end

  module Entity
    PROXY_METHOD_OPTIONS = {
      relative_path_from: {
        entity_to_pathname_args: [0]
      }
    }

    class << self
      def included(klass)
        klass.class_eval do
          attr_reader :pathname
        end

        klass.extend(ClassMethods)
      end
    end

    module ClassMethods
      def register_filesystem_permission_class(
        class_name,
        chmod_octal: nil,
        user: nil,
        group: nil
      )
        (@permission_classes ||= {})[class_name.to_sym] = PermissionOptions.new(
          chmod_octal,
          user,
          group
        )
      end

      def filesystem_permission_classes
        @permission_classes || {}
      end

      def unregister_all_filesystem_permission_classes
        @permission_classes&.clear
      end
    end

    # instance methods
    def initialize(path, permission_class: nil, parent: nil)
      @pathname = pathname_from_input(path)
      @permission_class = permission_class
      @parent = parent
    end

    def to_s
      pathname.to_s
    end

    # anything these objects can't respond to send to the pathname object
    def method_missing(method_name, *args, &block)
      if pathname.respond_to?(method_name)
        if PROXY_METHOD_OPTIONS.key?(method_name)
          PROXY_METHOD_OPTIONS.dig(method_name, :entity_to_pathname_args).each do |arg_number|
            if args[arg_number].class.include?(FileSystemAuth::Entity)
              args[arg_number] = args[arg_number].pathname
            end
          end
        end

        pathname.send(method_name, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      pathname.respond_to?(method_name, include_private)
    end

    def apply_permissions!(bubble_up: false)
      return unless pathname.exist?

      po = permission_options

      if po.chmod_octal
        FileUtils.chmod(po.chmod_octal, pathname)
      end

      if po.user || po.group
        FileUtils.chown(po.processed_user, po.processed_group, pathname)
      end

      if bubble_up && has_parent?
        @parent.apply_permissions!(bubble_up: true)
      end
    end

    private

    def pathname_from_input(input)
      if input.is_a?(String)
        Pathname.new(input)
      elsif input.is_a?(Pathname)
        input
      else
        nil
      end
    end

    def permission_options
      if @permission_class && (permission_options = self.class.filesystem_permission_classes[@permission_class.to_sym])
        permission_options
      else
        PermissionOptions.new(nil, nil, nil)
      end
    end

    def has_parent?
      !@parent.nil?
    end
  end

  class Dir
    include FileSystemAuth::Entity

    def join(path, type: :dir, permission_class: nil)
      const = FileSystemAuth.const_get(type.to_s.capitalize)
      const.new(pathname.join(path), permission_class: permission_class, parent: self)
    end

    def create!
      return if pathname.exist?

      @parent.create! if @parent

      FileUtils.mkdir(pathname)

      apply_permissions!
    end

    def delete
      FileUtils.rm_rf(pathname)
    end
  end

  class File
    include FileSystemAuth::Entity

    def basename_without_extname
      pathname.basename('.*')
    end

    def prepare
      @parent.create!

      yield(pathname)

      apply_permissions!
    end
  end
end
