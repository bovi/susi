# create standard task to execute the tests
task :default => :test

# Path: Rakefile
# create a task to execute the tests
task :test do
  ruby "lib/susi.rb"
end

# cleanup gem build
task :clean do
  # remove susi-qemu-*.gem
  rm_rf Dir['susi-qemu-*.gem'] 
end

task :build do
  sh "gem build susi.gemspec"
end

task :push do
  sh "gem push"
end
