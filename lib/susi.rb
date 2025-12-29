#!/usr/bin/env ruby

require_relative 'qmp'
require_relative 'vm'
require_relative 'ssh'
require_relative 'vnc'
require_relative 'disk'
require_relative 'output'

require 'yaml'
require 'securerandom'
require 'open-uri'

module Susi
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
init:
  - date
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
    usb = config['usb']
    shared_dir = config['shared_dir'] || '.'
    dpkg = config['dpkg']
    cpu_count = config['cpu_count'] || 1
    memory = config['memory'] || 2048
    disk_template = "#{TEMPLATE_DIR}/#{config['template']}"

    # check if vm is already running
    if VM.running?(name)
      raise "VM #{name} is already running"
    end

    # check if disk exist, if not clone it
    disk_name = "#{DISK_DIR}/#{id}"
    if !File.exist?("#{disk_name}.qcow2")
      Susi::debug "Disk not found, cloning..."
      Disk.clone(disk_template, disk_name)

      VM.start(name, disk_name, usb: usb,
                shared_dir: shared_dir, cpu_count: cpu_count,
                memory: memory)

      # SSH into VM and set hostname
      SSH.set_hostname(name)
      SSH.setup_virtio_filesystem(name)

      SSH.apt_update(name)
      SSH.apt_upgrade(name)

      if dpkg
        SSH.install_dpkg(name, dpkg)
      end

      init_commands = config['init']
      if init_commands && init_commands.is_a?(Array)
        Susi::info "Executing init commands from .susi.yml..."
        SSH.login(name) do |vm, ssh|
          init_commands.each do |command|
            Susi::debug "Executing: #{command}"
            output = ssh.exec!(command)
            Susi::debug "Output: #{output}"
          end
        end
        Susi::info "Init commands execution complete."
      end

      # Reboot the VM
      SSH.reboot(name)
    else
      VM.start(name, disk_name, usb: usb,
                shared_dir: shared_dir, cpu_count: cpu_count,
                memory: memory)
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
      Susi::debug "removing #{disk_name}"
      File.delete(disk_name)
    end
  end

  def self.add_usb
    if !File.exist?(CONFIG_FILE)
      raise "susi is not initialized"
    end

    config = YAML.load_file(CONFIG_FILE)
    usb = config['usb'] || []

    Susi::info "Starting USB Device assistant..."
    Susi::info "I'm helping you to add a new USB device to the VM"
    Susi::info "Please ensure that the new USB device is not connect yet!"
    devices = []
    `lsusb`.each_line do |dev|
      next unless dev =~ /^Bus/
      m = dev.split /\s/
      m = m[5]
      next unless m =~ /^[a-f0-9]{4,4}\:[a-f0-9]{4,4}$/
      Susi::debug "Found #{m}"
      devices << m
    end
    Susi::info "Connect the new USB device... (press ENTER when ready)"
    gets
    `lsusb`.each_line do |dev|
      next unless dev =~ /^Bus/
      m = dev.split /\s/
      m = m[5]
      next unless m =~ /^[a-f0-9]{4,4}\:[a-f0-9]{4,4}$/
      next if devices.include? m
      Susi::info "Found new USB device: #{m}"
      usb << m
    end

    config['usb'] = usb
    File.open(CONFIG_FILE, 'w') do |f|
      f.puts config.to_yaml
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
      assert_equal(false, run_command("ruby ./bin/susi"))
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
      assert_equal(true, run_command("ruby ./bin/susi disk create test 1"))
      assert(File.exist?("test.qcow2"))
      run_command("rm test.qcow2")
    end

    def test_cli_create_img_fail
      assert_equal(false, run_command("ruby ./bin/susi disk create test"))
      assert_equal(false, run_command("ruby ./bin/susi disk create test pest"))
      assert_equal(false, run_command("ruby ./bin/susi disk create 1"))
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
      assert_equal(true, run_command("ruby ./bin/susi disk create test 1"))
      assert_equal(true, run_command("ruby ./bin/susi disk clone test clone"))
      assert(File.exist?("clone.qcow2"))
      run_command("rm clone.qcow2")
      run_command("rm test.qcow2")
    end

    def test_cli_clone_img_fail
      assert_equal(false, run_command("ruby ./bin/susi disk clone test clone"))
      assert_equal(true, run_command("ruby ./bin/susi disk create test 1"))
      assert_equal(false, run_command("ruby ./bin/susi disk clone test"))
      assert_equal(true, run_command("ruby ./bin/susi disk clone test clone"))
      assert_equal(false, run_command("ruby ./bin/susi disk clone test clone"))

      run_command("rm clone.qcow2")
      run_command("rm test.qcow2")
    end
  end
end
