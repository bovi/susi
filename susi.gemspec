require_relative 'lib/version'

Gem::Specification.new do |s|
  s.name        = 'susi-qemu'
  s.version     = Susi::VERSION
  s.summary     = 'Manage project QEMU instances'
  s.description = 'Config, manage, and maintain multiple QEMU instances for your projects'
  s.authors     = ['Daniel Bovensiepen']
  s.email       = 'oss@bovi.li'
  s.files       = Dir['lib/*.rb'] + Dir['lib/novnc/**/*.{html,js}']
  s.executables << 'susi'
  s.homepage    = 'https://github.com/bovi/susi'
  s.license     = 'MIT'
  s.metadata    = {
    'source_code_uri' => 'https://github.com/bovi/susi'
  }
  s.add_dependency 'net-ssh', '~> 7.2.0'
  s.add_dependency 'ed25519', '~> 1.3.0'
  s.add_dependency 'bcrypt_pbkdf', '~> 1.1.1'
end
