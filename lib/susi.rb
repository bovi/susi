#!/usr/bin/env ruby

require 'test/unit'

module Susi
  class Disk
    def self.create(name, size)
      system("qemu-img create -f qcow2 #{name}.qcow2 #{size}G")
    end

    def self.clone(name, clone)
      system("qemu-img create -f qcow2 -F qcow2 -b #{name}.qcow2 #{clone}.qcow2")
    end
  end
end

# perform a test when the script is run
if __FILE__ == $0
  class SusiTest < Test::Unit::TestCase
    def test_cli_empty
      assert_equal(false, system("ruby ./susi.rb"))
    end

    def test_create_img
      Susi::Disk.create("test", "1")

      # check created file
      assert(File.exist?("test.qcow2"))
      info = `qemu-img info test.qcow2`
      assert(info.include?("virtual size: 1 GiB"))
      assert(info.include?("format: qcow2"))

      system("rm test.qcow2")
    end

    def test_cli_create_img
      assert_equal(true, system("ruby ./susi.rb disk create test 1"))
      assert(File.exist?("test.qcow2"))
      system("rm test.qcow2")
    end

    def test_cli_create_img_fail
      assert_equal(false, system("ruby ./susi.rb disk create test"))
      assert_equal(false, system("ruby ./susi.rb disk create test pest"))
      assert_equal(false, system("ruby ./susi.rb disk create 1"))
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

      system("rm clone.qcow2")
      system("rm test.qcow2")
    end

    def test_cli_clone_img
      assert_equal(true, system("ruby ./susi.rb disk create test 1"))
      assert_equal(true, system("ruby ./susi.rb disk clone test clone"))
      assert(File.exist?("clone.qcow2"))
      system("rm clone.qcow2")
      system("rm test.qcow2")
    end

    def test_cli_clone_img_fail
      assert_equal(false, system("ruby ./susi.rb disk clone test clone"))
      assert_equal(true, system("ruby ./susi.rb disk create test 1"))
      assert_equal(false, system("ruby ./susi.rb disk clone test"))
      assert_equal(true, system("ruby ./susi.rb disk clone test clone"))
      assert_equal(false, system("ruby ./susi.rb disk clone test clone"))

      system("rm clone.qcow2")
      system("rm test.qcow2")
    end
  end
end







































































