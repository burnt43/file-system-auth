require 'pathname'
require 'fileutils'
require 'active_support'

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
    extend ActiveSupport::Concern

    class_methods do
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
    end

    included do
      attr_reader :pathname
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

FileSystemAuth::Dir.register_filesystem_permission_class(:class1, chmod_octal: 06770)
FileSystemAuth::Dir.register_filesystem_permission_class(:class2, chmod_octal: 06750, group: (proc do 'ruby' end))
FileSystemAuth::File.register_filesystem_permission_class(:class1, chmod_octal: 00640, group: 'ruby')
foo = FileSystemAuth::Dir.new('/home/jcarson/tmp', permission_class: :class1)

foo
.join('foo', type: :dir, permission_class: :class1)
.create!

foo
.join('bar', type: :dir, permission_class: :class2)
.join('bar1', type: :dir, permission_class: :class2)
.join('bar2', type: :dir, permission_class: :class2)
.join('bar3', type: :dir, permission_class: :class2)
.join('bar4', type: :dir, permission_class: :class2)
.join('bar.txt', type: :file, permission_class: :class1)
.prepare do |pathname|
  File.open(pathname, 'w') do |f|
    f.puts 'Hello, World!'
  end
end
