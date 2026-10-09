require "nokogiri"
require "pathname"
require "tmpdir"
require "uri"
require "yaml"

root = File.expand_path("..", __dir__)
host = URI(YAML.safe_load_file(File.join(root, "_config.yml"))["url"]).host

Dir.mktmpdir("website-check-") do |destination|
  Dir.chdir(root) do
    exit 1 unless system("bundle", "exec", "jekyll", "build", "--destination", destination)
  end

  links = Hash.new { |hash, path| hash[path] = [] }
  Dir.glob(File.join(destination, "**", "*.html")).each do |file|
    Nokogiri::HTML(File.read(file)).css("a[href]").each do |link|
      uri = URI.parse(link["href"])
      next unless uri.host.nil? || uri.host == host
      next unless uri.path&.start_with?("/blog/categories/")

      links[uri.path] << Pathname(file).relative_path_from(Pathname(destination)).to_s
    rescue URI::InvalidURIError
      next
    end
  end

  abort "No category links found; check the build output." if links.empty?
  missing = links.reject do |path, _|
    target = File.join(destination, URI::DEFAULT_PARSER.unescape(path).delete_prefix("/"))
    File.file?(target) || File.file?(File.join(target, "index.html"))
  end
  missing.each { |path, sources| warn "Missing #{path} (linked from #{sources.uniq.first})" }
  abort "#{missing.size} category destinations missing." unless missing.empty?

  puts "PASS: all #{links.size} category destinations resolve."
end
