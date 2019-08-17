require 'minitest/pride'
require 'minitest/autorun'
require Pathname.new(__FILE__).parent.parent.join('lib', 'file-system-auth.rb')

module FileSystemAuth::Testing
  EntityProps = Struct.new(:flags, :user, :group)

  class Test < Minitest::Test
    def setup
      @scratch_area = Pathname.new(__FILE__).parent.join('scratch_area')
    end

    def teardown
      if @scratch_area.exist?
        FileUtils.rm_rf(@scratch_area)
      end
    
      [FileSystemAuth::Dir, FileSystemAuth::File].each(&:unregister_all_filesystem_permission_classes)
    end

    private

    def entity_props(pathname)
      result = %x[ls -ld #{pathname.to_s}]
      data = result.split

      EntityProps.new(data[0], data[2], data[3])
    end
  end
end
