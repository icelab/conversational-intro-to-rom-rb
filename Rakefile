require "fileutils"

task :build, [:part_name] do |t, args|
  FileUtils.rm_rf "tmp"
  FileUtils.mkdir "tmp"

  Dir["*.rb"].each do |source_file|
    system "docco --layout classic --output tmp #{source_file}"
    abort "docco failed" unless $?.success?
  end

  system "git co gh-pages"
  abort "could not checkout gh-pages" unless $?.success?

  FileUtils.mv "tmp/index.html", "index.html" if File.exist?("tmp/index.html")
  FileUtils.mv "tmp/intro.html", "#{args[:part_name]}.html"
end
