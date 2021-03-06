
require 'builder'
require 'pathname'
require 'digest'
require 'mime/types'
require 'time'
require 'nokogiri'
require 'uri'

##
# Because hash can't just be a string. We need to specify what type.

class Metalink4FileHash
  attr_accessor :hash_value,
    :hash_type,
    :piece
 
  def initialize(opts = {})
    opts = opts.inject({}){ |r, (k,v)| r[k.to_sym] = v; r }
    
    self.hash_value = opts.fetch(:hash_value, nil)
    self.hash_type = opts.fetch(:hash_type, nil)
    self.piece = opts.fetch(:piece, nil)
  end
  
  ##
  # Hash must be in hexidecimal, lowercase
  #
  def hash_value=(v)
    raise ("Improper Format '%s'" % v) if v && v !~ /[0-9a-f]+/
    @hash_value = v
  end
  
  ##
  # sha-256
  #
  def hash_type=(v)
    @hash_type = v
  end
  
  ##
  # nil if of whole file.
  #
  def piece=(v)
    @piece = v
  end

end



##
# Describes the download urls of files listed in the Metalink 4 file
class Metalink4FileUrl
  attr_accessor :url,
    :priority,
    :location
  ##
  # Options: url, location, priority.
  # if only a string it profided it must be the URL.
  def initialize(opts = {})
    
    self.priority = 1
    case opts
    when String
      self.url = opts
    when Hash
      opts = opts.inject({}){ |r, (k,v)| r[k.to_sym] = v; r }
      self.url = opts[:url]
      self.location = opts[:location]
      self.priority = opts[:priority]
    else
      raise "URL format %s" % opts.inspect
    end
  end

  ##
  # URI of remote file, HTTPS, HTTP, FTP, Bittorrent, etc.
  # One, Required.
  def url=(v)
    @url = v ? URI.parse(v) : nil
  end
  
  ##
  # ISO3166-1 2 character country code
  # Client may ignore this field if a country code is not explicitly specified.
  # One, optional.
  def location=(v)
    raise "Improper format" if v && v.to_s !~ /[a-z]{2}/
    @location = v
  end
  
  ##
  # Priority this url is to be considered in. 1 is top level, 999999 is absolulte last. Duplicates allowed.
  # Defaults to 1 if not specified.
  def priority=(v)
    @priority = [[v.to_i, 1].max, 999999].min 
  end
  
  ##
  # Fragement call for builder.
  # For internal use.
  def render(builder_metalink_file, local_path)
    begin
      if MIME::Types.type_for(local_path.to_s).first == MIME::Types.type_for( self.url.path ).first
        builder_metalink_file.url(
          self.url.to_s, {
            location: self.location,
            priority: self.priority || 1,
            }.delete_if{ |k, v| v.nil? }
          )
      else
        builder_metalink_file.metaurl(
          self.url.to_s, {
            priority: self.priority || 1,
            mediatype: self.url.path =~ /\.torrent/ ? "torrent" : MIME::Types.type_for( self.url.path ).first.to_s
            }.delete_if{ |k, v| v.nil? }
          )
      end
    rescue
      puts [local_path, self.url]
      throw [local_path, self.url]
    end
  end
end

##
#Describes the files listed in the Metalink 4 file
class Metalink4File

  attr_accessor :local_path,
    :copyright,
    :description,
    :identity,
    :language,
    :logo,
    :os,
    :urls,
    :publisher_name,
    :publisher_url,
    :signature,
    :version,
    :piece_size,
    :piece_count,
    :hashes,
    :size
    
  ##
  # Options: local_path, copyright, description, identity, language, logo, os, urls, publisher_name, publisher_url, signature, version, piece_size, piece_count
  def initialize(opts = {})
    opts = opts.inject({}){ |r, (k,v)| r[k.to_sym] = v; r }
    
    self.language = []
    self.os = []
    
  
    self.local_path = opts.fetch(:local_path, nil)
    self.copyright = opts.fetch(:copyright, nil)
    self.description = opts.fetch(:description, nil)
    self.identity = opts.fetch(:identity, nil)
    case opts.fetch(:language, nil)
    when Array
        self.language = opts.fetch(:language, nil)
    when String
        self.language = [opts.fetch(:language, nil)]
    end
    
    self.logo = opts.fetch(:logo, nil)
    case opts.fetch(:os, nil)
    when Array
        self.os = opts.fetch(:os, nil)
    when String
        self.os = [opts.fetch(:os, nil)]
    end

    self.urls = []
    opts.fetch(:urls, []).each do |url|
      self.urls << Metalink4FileUrl.new(url)
    end
      
    self.publisher_name = opts.fetch(:publisher_name, nil)
    self.publisher_url = opts.fetch(:publisher_url, nil)
    self.signature = opts.fetch(:signature, nil)
    self.version = opts.fetch(:version, nil)
    
    self.piece_size = opts.fetch(:piece_size, nil) 
    self.piece_count = opts.fetch(:piece_count, nil) 
    
    self.hashes = []
  end
  
  ##
  # Path of local instance of file, relative to current working directory. 
  # relative path may be reproduced on the client side. MUST NOT include '.' or '..'
  # Must not include an absolute path ( begin with / or drive letter )
  #
  # use File.chdir if you must to achive this
  # Required
  def local_path=(v)
    return unless v
    @local_path = Pathname.new(v)
    raise "No absolute paths" if @local_path.absolute?
    raise "No dots" if @local_path.to_s =~ /\.\/|\.\\/
    @local_path
  end
  

  ##
  # The copyright of the file, human readble. URL should be ok, Or a full text.
  # Lack of this field does not assert ANY paticular state of copyright.
  # One, optional.
  def copyright=(v)
    @copyright = v
  end
  
  
  ##
  # if "Firefox 3.5" the description would be "A Web Browser"
  # Human readable.
  # One, optional, but reccomended.
  def description=(v)
    @description = v
  end
  
  ##
  # if "Firefox 3.5" the identity would be "Firefox"
  # Human readable.
  # One, optional.
  def identity=(v)
    @identity = v
  end
  
  ##
  # The language supported by the file. 
  # In rfc5646 format
  # See: https://datatracker.ietf.org/doc/html/rfc5646
  # One or more, optional.
  def language=(v)
    @language = v.is_a?(String) ? [v] : v 
  end
  
  ##
  # Logo is the URL of an image file associated with this file. This can be an icon or avatar.
  # It should be square, and support low resolutions.
  # One, optional.
  def logo=(v)
    @logo = v ? URI.parse(v) : nil
  end
  
  ##
  # Operating System this download supports. One or more, optional.
  # See IANA registry named "Operating System Names"
  # at https://www.iana.org/assignments/operating-system-names/operating-system-names.xhtml
  def os=(v)
    @os = v.is_a?(String) ? [v] : v
  end
  
  ##
  # The creator of this meta4 file, which may be differnt than the files refrenced within.
  # One, Optional.
  def publisher_name=(v)
    @publisher_name = v
  end
  
  ##
  # THE URL of the publisher, a descriptive page, NOT the source of this .meta4 file.
  # One, Optional.
  def publisher_url=(v)
    @publisher_url = v ? URI.parse(v) : nil
  end
  
  
  ##
  # OpenPGP Or somthing. The signature should match the referenced file.
  # One, Optional.
  def signature=(v)
    @signature = v
  end
  
  ##
  # if "Firefox 3.5" the version would be "3.5"
  # Human readable.
  # One, optional.
  def version=(v)
    @version = v
  end
  
  ##
  # Overwrite any present hashes. If no path is provided, checksum will be attempted of local_file.
  # This might require a Dir.chdir.
  #
  # There is no protection of what this path can call - please sanitize any input to make sure files
  # outside your project can't be checksummed. 
  #
  # options: debug - show full path on error dump, piece_size - bytes, integer, OR piece_count - integer
  #
  # These hashes will be SHA256
  def checksum!(path = nil, opts = {})
    opts = opts.inject({}){ |r, (k,v)| r[k.to_sym] = v; r }
  
    raise "Path uses differnt extension" if path && File.extname(path) != File.extname(self.local_path)
  
  
    if opts[:debug]
     raise ("File '%s' does not exist" % File.expand_path( path ) ) if path && !File.exist?( File.expand_path( path ) )
    else
      raise ("File '%s' does not exist" % path ) if path && !File.exist?( File.expand_path( path ) )
    end
    
    raise "Can not specify both piece_size and piece_count" if opts[:piece_size] && opts[:piece_count]
    raise "piece_size must be an Integer" if opts[:piece_size] && !opts[:piece_size].is_a?(Integer)
    raise "piece_count must be an Integer" if opts[:piece_count] && !opts[:piece_count].is_a?(Integer)
  
    path ||= self.local_path
  
    #get filesize
    self.size = File.size( File.expand_path( path ) )

    # Overrides piece_count if set
    # minimum size of 1KB for a piece
    if opts[:piece_size]
      @piece_count = nil
      @piece_size = [opts[:piece_size], 1024].max
    end


    # Overrides piece_size if set
    # This will be a multiple of 1024, and the last file will be slightly smaller
    # this means 1KB is the minimum size for a piece
    if opts[:piece_count]
      @piece_count = opts[:piece_count]
      @piece_size = ((@size / @piece_count) / 1024.0).ceil * 1024 
    end

    self.hashes = []
    self.hashes << Metalink4FileHash.new( hash_value: Digest::SHA256.file( File.expand_path( path ) ).hexdigest, hash_type: "sha-256" )
    if self.piece_size
      i = 0
      (0...@size).step(self.piece_size).each do |offset|
        self.hashes << Metalink4FileHash.new( hash_value: Digest::SHA256.hexdigest(File.read(File.expand_path( path ), self.piece_size, offset)), hash_type: "sha-256", piece: i )
        i += 1
      end
    end
  end

  
  ##
  # Fragement call for builder. 
  # For internal use.
  def render(builder_metalink, metalink4)
  
    raise "Local path required" if !@local_path
    #raise ("Local path '%s' does not match any files" % @local_path) if File.exist?(@local_path) || !self.hashes.empty?

    #build up hashes if none were imported
    if self.hashes.empty? && File.exist?(@local_path)
      self.checksum!
    end

    metalink4.file( name: self.local_path ) do |metalink_file|
      metalink_file.copyright( ("\n%s\n" % self.copyright) ) if self.copyright
      metalink_file.description( self.description ) if self.description
      metalink_file.identity( self.identity ) if self.identity 

      self.hashes.select{ |x| x.piece.nil? }.each do |hash|
        metalink_file.hash(hash.hash_value, type: hash.hash_type)
      end
      
      #multiple languages possible
      self.language.each do |language|
        metalink_file.language( language )
      end if self.language

      metalink_file.logo( self.logo ) if self.logo
      
      #multiple operating systems possible
      self.os.each do |os|
        metalink_file.os( os )
      end if self.os
      
      self.urls.each do |file_url|
        file_url.render(
          metalink_file,
          self.local_path
          )
      end if self.urls
      
      metalink_file.pieces(length: self.piece_size, type: self.hashes.select{ |x| x.piece }.first.hash_type) do |pieces|
        self.hashes.select{ |x| x.piece }.sort_by(&:piece).each do |hash|
          metalink_file.hash(hash.hash_value)
        end
      end if self.hashes.any?{ |x| x.piece }
          
      metalink_file.publisher( name: self.publisher_name, url: self.publisher_url.to_s) if self.publisher_name || self.publisher_url

      #what other type is it going to be
      metalink_file.signature( ("\n%s\n" % self.signature), mediatype: "application/pgp-signature" ) if self.signature

      metalink_file.size( self.size ) #SHOULD, file bytesize
      metalink_file.version( self.version ) if self.version
    end
  end
  
  

  ##
  # One of two options to enable piece hashes
  # Overrides piece_count if set
  # minimum size of 1KB for a piece
  def piece_size=(v)
    return unless v
    @piece_count = nil
    @piece_size = [v, 1024].max
  end

private

  ##
  # private becaue checksum! is a preferred call
  # One of two options to enable piece hashes
  # Overrides piece_size if set
  # This will be a multiple of 1024, and the last file will be slightly smaller
  # this means 1KB is the minimum size for a piece
  def piece_count=(v)
    return if v.nil?
    @piece_count = v
    @piece_size = ((@local_path.size / v) / 1024.0).ceil * 1024 
  end
  
  
end

##
# Describes the base Metalink 4 file as specified by rfc5854
# If served, it should have a header of application/metalink4+xml
# https://en.wikipedia.org/wiki/Metalink
class Metalink4

  attr_accessor :files,
    :published,
    :updated,
    :origin,
    :origin_dynamic,
    :xml

  ##
  # Options: files, published, updated, origin, origin_dynamic
  def initialize(opts = {})
    opts = opts.inject({}){ |r, (k,v)| r[k.to_sym] = v; r }
  
    self.files = []
    
    opts.fetch(:files, []).each do |file|
      self.files << Metalink4File.new(file)
    end

    self.published = opts.fetch(:published, nil)
    self.updated = opts.fetch(:updated, nil)
    self.origin = opts.fetch(:origin, nil)
    self.origin_dynamic = opts.fetch(:origin_dynamic, false)

    self.xml = Builder::XmlMarkup.new(indent: 2)
  end
  
  ##
  # original publish date. Equivelent of ActiveRecord's created_at
  # One, Optional.
  def published=(v)
    case v
    when Time, nil
      @published = v
    when String
      @published = Time.parse(v)
    else
      raise "Not a Time"
    end
    @published 
  end
  
  ##
  # last publish date. Equivelent of ActiveRecord's updated_at
  # One, Optional.
  def updated=(v)
    case v
    when Time, nil
      @updated = v
    when String
      @updated = Time.parse(v)
    else
      raise "Not a Time"
    end
    @updated 
  end
  
  ##
  # url this meta4 file was made available at. Updates are potentially at the same url.
  # One, Optional, but should.
  def origin=(v)
    @origin = v ? URI.parse(v) : nil
  end
  
  ##
  # if the meta4 file may have an update available
  # Defaults to false.
  def origin_dynamic=(v)
    @origin = !!v
  end
  

  ##
  # Render to XML, returns string.
  #
  # Checksums are calculated at this point. ONLY sha-256 is calculated.
  def render
  
    raise "files not specified" if self.files.empty?
  
    self.xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
    self.xml.metalink( xmlns: "urn:ietf:params:xml:ns:metalink" ) do |metalink|
    
      metalink.generator("Sudrien/metalink-ruby 0.2.0") #may
      metalink.origin( self.origin, dynamic: self.origin_dynamic ) if self.origin
      
      metalink.published( self.published.strftime('%FT%T%:z') ) if self.published
      metalink.updated( self.updated.strftime('%FT%T%:z') ) if self.updated
    
      self.files.each do |file|
        file.render(self, metalink)
      end
    end
    self.xml.target!
  end

  ##
  # Read a .meta4 to internal model. Takes either a file path or XML sting.
  #
  # Will import any provided hashes, so nothing needs to be calculated.
  def self.read(potential_file_path)

    begin
      if File.exist?(potential_file_path)
        doc = File.open(potential_file_path) { |f| Nokogiri::XML(f) }
      elsif potential_file_path.is_a?(String)
        doc = Nokogiri::XML(potential_file_path)
      end
    rescue
      raise "%s Not an XML File" % potential_file_path
    end

    ret = Metalink4.new
    ret.published = doc.at("metalink > published").content 
    ret.updated = doc.at("metalink > updated").content rescue nil
    ret.origin = doc.at("metalink > origin").content rescue nil
    ret.origin_dynamic = doc.at("metalink > origin[dynamic]").content == "true" rescue false

    doc.search("metalink > file").each do |file|
    
      ret.files << Metalink4File.new

      ret.files.last.local_path = file.attr("name")

      ret.files.last.copyright = file.at("copyright").content rescue nil
      ret.files.last.description = file.at("description").content rescue nil
      ret.files.last.identity = file.at("identity").content rescue nil
      ret.files.last.language = file.at("language").content rescue nil
      ret.files.last.logo = file.at("logo").content rescue nil
      ret.files.last.os = file.at("os").content rescue nil
      ret.files.last.publisher_name = file.at("publisher[name]").content rescue nil
      ret.files.last.publisher_url = file.at("publisher[url]").content rescue nil
      ret.files.last.signature = file.at("signature").content rescue nil
      ret.files.last.version = file.at("version").content rescue nil
      
      (file.search("hash") - file.search("pieces > hash")).each do |hash|
        ret.files.last.hashes << Metalink4FileHash.new
        ret.files.last.hashes.last.hash_value = hash.content rescue nil
        ret.files.last.hashes.last.hash_type = hash.attr("type") rescue nil
      end

      ret.files.last.piece_size = file.at("pieces").attr("length").to_i rescue nil
      piece_type = file.at("pieces").attr("type") rescue nil


      ret.files.last.hashes  ||= []
      file.search("pieces > hash").each_with_index do |hash, hash_piece_index|
        ret.files.last.hashes << Metalink4FileHash.new
        ret.files.last.hashes.last.hash_value = (hash.content rescue nil)
        ret.files.last.hashes.last.hash_type = piece_type
        ret.files.last.hashes.last.piece = hash_piece_index
      end
      
      file.search("url").each do |url|
        ret.files.last.urls << Metalink4FileUrl.new
        ret.files.last.urls.last.url = url.content rescue nil
        ret.files.last.urls.last.location = url.attr("location") rescue nil
        ret.files.last.urls.last.priority = url.attr("priority") rescue nil
      end
      
      file.search("metaurl").each do |metaurl|
        ret.files.last.urls << Metalink4FileUrl.new
        ret.files.last.urls.last.url = metaurl.content rescue nil
        ret.files.last.urls.last.priority = metaurl.attr("priority") rescue nil
      end
    end
    
    ret
  end
end
