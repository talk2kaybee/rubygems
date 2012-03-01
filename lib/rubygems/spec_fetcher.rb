require 'rubygems/remote_fetcher'
require 'rubygems/user_interaction'
require 'rubygems/errors'
require 'rubygems/text'
require 'rubygems/name_tuple'

##
# SpecFetcher handles metadata updates from remote gem repositories.

class Gem::SpecFetcher

  include Gem::UserInteraction
  include Gem::Text

  ##
  # Cache of latest specs

  attr_reader :latest_specs # :nodoc:

  ##
  # Cache of all released specs

  attr_reader :specs # :nodoc:

  ##
  # Cache of prerelease specs

  attr_reader :prerelease_specs # :nodoc:

  @fetcher = nil

  def self.fetcher
    @fetcher ||= new
  end

  def self.fetcher=(fetcher) # :nodoc:
    @fetcher = fetcher
  end

  def initialize
    @dir = File.join Gem.user_home, '.gem', 'specs'
    @update_cache = File.stat(Gem.user_home).uid == Process.uid

    @specs = {}
    @latest_specs = {}
    @prerelease_specs = {}

    @caches = {
      :latest => @latest_specs,
      :prerelease => @prerelease_specs,
      :released => @specs,
    }

    @fetcher = Gem::RemoteFetcher.fetcher
  end

  ##
  #
  # Find and fetch gem name tuples that match +dependency+.
  #
  # If +matching_platform+ is false, gems for all platforms are returned.

  def search_for_dependency(dependency, matching_platform=true)
    found = {}

    rejected_specs = {}

    if dependency.prerelease?
      type = :complete
    elsif dependency.latest_version?
      type = :latest
    else
      type = :released
    end

    available_specs(type).each do |source, specs|
      found[source] = specs.select do |tup|
        if dependency.match?(tup)
          if matching_platform and !Gem::Platform.match(tup.platform)
            pm = (
              rejected_specs[dependency] ||= \
                Gem::PlatformMismatch.new(tup.name, tup.version))
            pm.add_platform tup.platform
            false
          else
            true
          end
        end
      end
    end

    errors = rejected_specs.values

    tuples = []

    found.each do |source, specs|
      specs.each do |s|
        tuples << [s, source]
      end
    end

    tuples = tuples.sort_by { |x| x[0] }

    return [tuples, errors]
  end


  ##
  # Return all gem name tuples who's names match +obj+

  def detect(type=:complete)
    tuples = []

    available_specs(type).each do |source, specs|
      specs.each do |tup|
        if yield(tup)
          tuples << [tup, source]
        end
      end
    end

    tuples
  end


  ##
  # Find and fetch specs that match +dependency+.
  #
  # If +matching_platform+ is false, gems for all platforms are returned.

  def spec_for_dependency(dependency, matching_platform=true)
    tuples, errors = search_for_dependency(dependency, matching_platform)

    specs = tuples.map do |tup, source|
      [source.fetch_spec(tup), source]
    end

    return [specs, errors]
  end

  ##
  # Suggests a gem based on the supplied +gem_name+. Returns a string
  # of the gem name if an approximate match can be found or nil
  # otherwise. NOTE: for performance reasons only gems which exactly
  # match the first character of +gem_name+ are considered.

  def suggest_gems_from_name gem_name
    gem_name        = gem_name.downcase
    max             = gem_name.size / 2
    names           = available_specs(:complete).values.flatten(1)

    matches = names.map { |n|
      next unless n.match_platform?

      distance = levenshtein_distance gem_name, n.name.downcase

      next if distance >= max

      return [n.name] if distance == 0

      [n.name, distance]
    }.compact

    matches = matches.uniq.sort_by { |name, dist| dist }

    matches.first(5).map { |name, dist| name }
  end

  ##
  # Returns a list of gems available for each source in Gem::sources.
  #
  # +type+ can be one of 3 values:
  # :released   => Return the list of all released specs
  # :complete   => Return the list of all specs
  # :latest     => Return the list of only the highest version of each gem
  # :prerelease => Return the list of all prerelease only specs
  # 

  def available_specs(type)
    list = {}

    Gem.sources.each_source do |source|
      case type
      when :latest
        list[source] = tuples_for source, :latest
      when :released
        list[source] = tuples_for source, :released
      when :complete
        tuples = tuples_for(source, :prerelease) \
               + tuples_for(source, :released)

        list[source] = tuples
      when :prerelease
        list[source] = tuples_for(source, :prerelease)
      end
    end

    list
  end

  def tuples_for(source, type)
    list  = {}
    cache = @caches[type]

    cache[source.uri] ||= source.load_specs(type)
  end
end

