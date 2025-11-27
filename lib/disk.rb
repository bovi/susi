require_relative 'output'

module Susi
  class Disk
    DEFAULT_IMG = "debian-13.2.0-amd64-netinst.iso"

    def self.download_debian_netinstall
      # Check if ~/.susi directory exists, if not create it
      susi_dir = File.expand_path("~/.susi")
      Dir.mkdir(susi_dir) unless Dir.exist?(susi_dir)

      # Check if ~/.susi/iso directory exists, if not create it
      iso_dir = File.join(susi_dir, "iso")
      Dir.mkdir(iso_dir) unless Dir.exist?(iso_dir)

      # Set the output path to be in the iso directory
      output_path = File.join(iso_dir, DEFAULT_IMG)

      url = "https://mirrors.tuna.tsinghua.edu.cn/debian-cd/current/amd64/iso-cd/#{DEFAULT_IMG}"
      
      Susi::debug "Downloading Debian netinstall ISO..."
      
      begin
        Susi::debug "url: #{url}"
        URI.open(url) do |remote_file|
          File.open(output_path, "wb") do |local_file|
            local_file.write(remote_file.read)
          end
        end
        Susi::debug "Download completed successfully."
      rescue OpenURI::HTTPError => e
        Susi::debug "Error downloading the ISO: #{e.message}"
      rescue SocketError => e
        Susi::debug "Network error: #{e.message}"
      rescue => e
        Susi::debug "An unexpected error occurred: #{e.message}"
      end
    end

    def self.create(name, size)
      system("qemu-img create -f qcow2 #{name}.qcow2 #{size}G > /dev/null 2>&1")
    end

    def self.clone(name, clone)
      system("qemu-img create -f qcow2 -F qcow2 -b #{name}.qcow2 #{clone}.qcow2 > /dev/null 2>&1")
    end
  end
end
