require "fileutils"

task :build, [:part_name] do |t, args|
  FileUtils.rm_rf "tmp"
  FileUtils.mkdir "tmp"

  system "docco --layout classic --output tmp *.rb"

  system "git co gh-pages"

  FileUtils.mv "tmp/index.html", "index.html" if File.exist?("tmp/index.html")
  FileUtils.mv "tmp/intro.html", "#{args[:part_name]}.html"
end
