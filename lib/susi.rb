#!/usr/bin/env ruby

require_relative 'qmp'
require_relative 'vm'
require_relative 'ssh'
require_relative 'vnc'
require_relative 'disk'


module Susi
  VERSION = '0.0.1'
end

# perform a test when the script is run
if __FILE__ == $0
  require 'test/unit'

  class SusiTest < Test::Unit::TestCase
    def run_command(cmd)
      system("#{cmd} > /dev/null 2>&1")
    end

    def test_cli_empty
      assert_equal(false, run_command("ruby ./susi.rb"))
    end

    def test_create_img
      Susi::Disk.create("test", "1")

      # check created file
      assert(File.exist?("test.qcow2"))
      info = `qemu-img info test.qcow2`
      assert(info.include?("virtual size: 1 GiB"))
      assert(info.include?("format: qcow2"))

      run_command("rm test.qcow2")
    end

    def test_cli_create_img
      assert_equal(true, run_command("ruby ./susi.rb disk create test 1"))
      assert(File.exist?("test.qcow2"))
      run_command("rm test.qcow2")
    end

    def test_cli_create_img_fail
      assert_equal(false, run_command("ruby ./susi.rb disk create test"))
      assert_equal(false, run_command("ruby ./susi.rb disk create test pest"))
      assert_equal(false, run_command("ruby ./susi.rb disk create 1"))
    end

    def test_clone_img
      Susi::Disk.create("test", "1")
      Susi::Disk.clone("test", "clone")

      assert(File.exist?("clone.qcow2"))
      info = `qemu-img info clone.qcow2`
      assert(info.include?("virtual size: 1 GiB"))
      assert(info.include?("format: qcow2"))
      assert(info.include?("backing file: test.qcow2"))
      assert(info.include?("backing file format: qcow2"))

      run_command("rm clone.qcow2")
      run_command("rm test.qcow2")
    end

    def test_cli_clone_img
      assert_equal(true, run_command("ruby ./susi.rb disk create test 1"))
      assert_equal(true, run_command("ruby ./susi.rb disk clone test clone"))
      assert(File.exist?("clone.qcow2"))
      run_command("rm clone.qcow2")
      run_command("rm test.qcow2")
    end

    def test_cli_clone_img_fail
      assert_equal(false, run_command("ruby ./susi.rb disk clone test clone"))
      assert_equal(true, run_command("ruby ./susi.rb disk create test 1"))
      assert_equal(false, run_command("ruby ./susi.rb disk clone test"))
      assert_equal(true, run_command("ruby ./susi.rb disk clone test clone"))
      assert_equal(false, run_command("ruby ./susi.rb disk clone test clone"))

      run_command("rm clone.qcow2")
      run_command("rm test.qcow2")
    end
  end
end
