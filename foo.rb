require 'pathname'
require 'fileutils'
require 'hashie'

module FileSystemAuth
  PermissionOptions = Struct.new(:chmod_octal, :user_name, :group_name) do
    def to_s
      "<#{self.class.name} chmod_octal=#{chmod_octal&.to_s(8)} user_name=#{user_name} group=#{group_name}>"
    end
  end

  module Entity
    module ClassMethods
      def register_filesystem_permission_class(
        class_name,
        chmod_octal: nil,
        user_name: nil,
        group_name: nil
      )
        (@permission_classes ||= {})[class_name.to_sym] = PermissionOptions.new(
          chmod_octal,
          user_name,
          group_name
        )
      end

      def filesystem_permission_classes
        @permission_classes || {}
      end
    end

    module InstanceMethods
      def initialize(path, permission_class: nil, parent: nil)
        @pathname = pathname_from_input(path)
        @permission_class = permission_class
        @parent = parent
      end

      def to_s
        "<#{self.class.name} path=#{@pathname.to_s} permissions=#{permission_options.to_s}>"
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
        if @permission_class.nil?
          {}
        else
          self.class.filesystem_permission_classes[@permission_class.to_sym] || {}
        end
      end
    end
  end

  class Dir
    extend  Entity::ClassMethods
    include Entity::InstanceMethods

    def join(path, type: :dir, permission_class: nil)
      const = FileSystemAuth.const_get(type.to_s.capitalize)
      const.new(@pathname.join(path), permission_class: permission_class, parent: self)
    end

    def create!
      return if @pathname.exist?

      @parent.create! if @parent

      po = permission_options

      FileUtils.mkdir(@pathname)

      if po.chmod_octal
        FileUtils.chmod(po.chmod_octal, @pathname)
      end

      if po.user_name || po.group_name
        FileUtils.chown(po.user_name, po.group_name, @pathname)
      end
    end
  end

  class File
    extend  Entity::ClassMethods
    include Entity::InstanceMethods
  end
end

FileSystemAuth::Dir.register_filesystem_permission_class(:class1, chmod_octal: 06770)
FileSystemAuth::Dir.register_filesystem_permission_class(:class2, chmod_octal: 06750, group_name: 'ruby')
foo = FileSystemAuth::Dir.new('/home/jcarson/tmp', permission_class: :class1)

foo
.join('foo', type: :dir, permission_class: :class1)
.create!

foo
.join('bar', type: :dir, permission_class: :class2)
.create!
