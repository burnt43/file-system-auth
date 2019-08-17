require Pathname.new(__FILE__).parent.join('test_helper.rb')

# NOTE: This test will basically only work in my environment. I'm using
#   groups and users that are pre-existing on my systems. This isn't
#   important to fix at present.
class FileSystemAuth::Testing::FileSystemAuthTest < FileSystemAuth::Testing::Test
  def test_features
    FileSystemAuth::Dir.register_filesystem_permission_class(
      :system
    )

    FileSystemAuth::Dir.register_filesystem_permission_class(
      :writeable_to_group,
      chmod_octal: 0o6770,
      group: (proc do
        'ruby'
      end)
    )

    FileSystemAuth::Dir.register_filesystem_permission_class(
      :read_only_to_group,
      chmod_octal: 0o6750,
      group: 'ruby'
    )

    FileSystemAuth::File.register_filesystem_permission_class(
      :writeable_to_group,
      chmod_octal: 0o660,
      group: 'ruby'
    )

    FileSystemAuth::File.register_filesystem_permission_class(
      :read_only_to_group,
      chmod_octal: 0o640,
      group: 'ruby'
    )

    top_level = FileSystemAuth::Dir.new(@scratch_area, permission_class: :system)

    top_level
      .join('foo1', type: :dir, permission_class: :system)
      .join('foo1-1', type: :dir, permission_class: :read_only_to_group)
      .join('foo1-1-1', type: :dir, permission_class: :writeable_to_group)
      .join('do_not_change.txt', type: :file, permission_class: :read_only_to_group)
      .prepare do |filename|
        File.open(filename, 'w') do |f|
          f.puts 'Hello, World!'
        end
      end

    # NOTE: This kind of testing is dumb. I'm testing the output of ls which
    #   is assuming a *nix style system. This is OK for now.
    props = entity_props(@scratch_area)
    assert_equal('drwxr-xr-x', props.flags)
    assert_equal('jcarson', props.user)
    assert_equal('jcarson', props.group)

    props = entity_props(@scratch_area.join('foo1'))
    assert_equal('drwxr-xr-x', props.flags)
    assert_equal('jcarson', props.user)
    assert_equal('jcarson', props.group)

    props = entity_props(@scratch_area.join('foo1', 'foo1-1'))
    assert_equal('drwsr-s---', props.flags)
    assert_equal('jcarson', props.user)
    assert_equal('ruby', props.group)

    props = entity_props(@scratch_area.join('foo1', 'foo1-1', 'foo1-1-1'))
    assert_equal('drwsrws---', props.flags)
    assert_equal('jcarson', props.user)
    assert_equal('ruby', props.group)

    props = entity_props(@scratch_area.join('foo1', 'foo1-1', 'foo1-1-1', 'do_not_change.txt'))
    assert_equal('-rw-r-----', props.flags)
    assert_equal('jcarson', props.user)
    assert_equal('ruby', props.group)

    dir =
      top_level
        .join('foo1', type: :dir, permission_class: :system)
        .join('foo1-2', type: :dir, permission_class: :system)

    dir.create!

    props = entity_props(@scratch_area.join('foo1', 'foo1-2'))
    assert_equal('drwxr-xr-x', props.flags)
    assert_equal('jcarson', props.user)
    assert_equal('jcarson', props.group)

    dir
      .join('change_me.txt', type: :file, permission_class: :writeable_to_group)
      .prepare do |filename|
        File.open(filename, 'w') do |f|
          f.puts 'PIYO HIGE'
        end
      end

    props = entity_props(@scratch_area.join('foo1', 'foo1-2', 'change_me.txt'))
    assert_equal('-rw-rw----', props.flags)
    assert_equal('jcarson', props.user)
    assert_equal('ruby', props.group)
  end
end
