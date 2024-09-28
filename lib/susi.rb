#!/usr/bin/env ruby

require_relative 'qmp'
require_relative 'vm'
require_relative 'ssh'
require_relative 'vnc'
require_relative 'disk'

require 'yaml'
require 'securerandom'

module Susi
  VERSION = '0.0.1'
  CONFIG_FILE = ".susi.yml"
  SUSI_DIR = "#{ENV['HOME']}/.susi"
  TEMPLATE_DIR = "#{SUSI_DIR}/templates"
  DISK_DIR = "#{SUSI_DIR}/disks"

  def self.current_vm_name
    if !File.exist?(CONFIG_FILE)
      raise "susi is not initialized"
    end

    # load config
    config = YAML.load_file(CONFIG_FILE)
    config['name'] || Dir.pwd.split('/').last
  end

  def self.init
    # check if .susi.yml exist, if not create it
    if !File.exist?(CONFIG_FILE)
      # create unique ID
      id = SecureRandom.uuid

      File.open(CONFIG_FILE, "w") do |file|
        file.puts <<-YAML
id: #{id}
template: DEFAULT
YAML
      end
    end
  end

  def self.start
    if !File.exist?(CONFIG_FILE)
      raise "susi is not initialized"
    end

    # load config
    config = YAML.load_file(CONFIG_FILE)
    id = config['id']
    name = config['name'] || Dir.pwd.split('/').last
    disk_template = "#{TEMPLATE_DIR}/#{config['template']}"

    # check if vm is already running
    if VM.running?(name)
      raise "VM #{name} is already running"
    end

    # check if disk exist, if not clone it
    disk_name = "#{DISK_DIR}/#{id}"
    if !File.exist?("#{disk_name}.qcow2")
      puts "Disk not found, cloning..."
      Susi::Disk.clone(disk_template, disk_name)

      Susi::VM.start(name, disk_name)

      # SSH into VM and set hostname
      Susi::SSH.set_hostname(name)
    else
      Susi::VM.start(name, disk_name)
    end
  end

  def self.rm
    if !File.exist?(CONFIG_FILE)
      raise "susi is not initialized"
    end

    # load config
    config = YAML.load_file(CONFIG_FILE)
    id = config['id']
    disk_name = "#{DISK_DIR}/#{id}.qcow2"

    if File.exist?(disk_name)
      # verbose remove file
      puts "removing #{disk_name}"
      File.delete(disk_name)
    end
  end
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
