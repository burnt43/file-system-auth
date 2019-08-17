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
    class << self
      def included(klass)
        klass.class_eval do
          attr_reader :pathname
        end

        klass.singleton_class.class_eval do
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
      end
    end

    # instance methods
    def initialize(path, permission_class: nil, parent: nil)
      @pathname = pathname_from_input(path)
      @permission_class = permission_class
      @parent = parent
    end

    def to_s
      "<#{self.class.name} path=#{pathname.to_s} permissions=#{permission_options.to_s}>"
    end

    def exist?
      pathname.exist?
    end

    private

    def apply_permissions!
      po = permission_options

      if po.chmod_octal
        FileUtils.chmod(po.chmod_octal, pathname)
      end

      if po.user || po.group
        FileUtils.chown(po.processed_user, po.processed_group, pathname)
      end
    end

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
  end

  class File
    include FileSystemAuth::Entity

    def prepare
      @parent.create!

      yield(pathname)

      apply_permissions!
    end
  end
end
