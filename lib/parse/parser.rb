# Peggy packrat parster for Ruby
# 
# parser.rb - packrat parser
#
# Copyright (c) 2006 Troy Heninger
#
# Peggy is copyrighted free software by Troy Heninger.
# You can redistribute it and/or modify it under the same terms as Ruby.

require 'pp'

# Peggy is a packrat parsing engine. Packrat parsers memoize every production so that 
# parses can happen in linear time. No production needs to be processed more than once for 
# a given position of the source. See http://pdos.csail.mit.edu/~baford/packrat/ for
# more details. 
# 
# Peggy also incorporates Parsing Expression Grammar (PEG) as proposed by Bryan Ford,
# as one of several input grammars. PEG is a formalized grammar specification needing 
# no separate lexer/scanner step. See http://pdos.csail.mit.edu/~baford/packrat/popl04/
# 
# As good as packrat parsers are, they have a few limitations. They cannot handle left
# recursion of a production, meaning a production cannot reference itself as the first
# element in a sequence. Also memoizing of production results means than memory consumption
# increasses with the size of the source being parsed. This is not usually a concern, execpt
# when attempting to parse multi-megabyte source files, such as a huge XML database.
module Peggy

  # Returned when a production did not match
  NO_MATCH = false
  # Used to prevent infinite (left) recursions
  IN_USE = true
  
#  class OrderedHash < Hash
#    alias_method :store, :[]=
#    alias_method :each_pair, :each
#
#    def initialize
#      @keys = []
#      super
#    end
#
#    def []=(key, val)
#      @keys << key
#      super
#    end
#
#    def delete(key)
#      @keys.delete(key)
#      super
#    end
#
#    def each
#      @keys.sort.each { |k| yield k, self[k] }
#    end
#
#    def each_key
#      @keys.sort.each { |k| yield k }
#    end
#
#    def each_value
#      @keys.sort.each { |k| yield self[k] }
#    end
#  end
  
  # Packrat parser class. Note all methods have a trailing exclamation (!) or question 
  # mark (?), or have long names with underscores (_). This is because productions are 
  # methods and we need to avoid name collisions. To use this class you must subclass 
  # Parser and provide your productions as methods. Your productions must call match? 
  # or one of the protected convenience routines to perform parsing. Productions must 
  # never call another production directly, or results will not get memoized and you 
  # will slow down your parse conciderably, and possibly risk getting into an infinite 
  # recursion (until the stack blows its top). Note, as a conveience in writting 
  # productions, you can call any match? function multiple times, passing each returned 
  # index, such as in a sequence, without checking the results of each production.
  class Parser
    
    # Tells parser to print intermediate results if set.
    attr_accessor :debug_flag

    # The source to parse, can be set prior to calling parse!().
    attr_accessor :source_text
    
    # The results of the parse. A hash (keys of indexs) of hashes (keys of production 
    # symbols and values of end indexes.
    attr_reader :parse_results

    # The productions to ignore.
    attr_accessor :ignore_productions

    # Return a range (or character) of the source_text.
    def [] range
      raise "source_text not set" if source_text.nil?
      source_text[range]
    end

    # Invokes the parser from the beginning of the source on the given production goal.
    # You may provide the source here or you can set source_text prior to calling.
    # If index is provided the parser will ignore characters previous to it.
    def parse? goal, source = nil, index = 0
      self.source_text = source unless source.nil?
        # Hash of automatic hashes
      @parse_results = Hash.new {|h1, k1| h1[k1] = {}} # OrderedHash.new {|h1, k1| h1[k1] = {}}
      @keys = nil
      index = match? goal, index
      pp(parse_results) if debug_flag
      index
    end

    # Queries the parse results for a heirarchy of production matches. An array of 
    # index ranges is returned, or an empny array if none are found. This can only be 
    # called after parse_results have been set by a parse.
    def query? *args
      raise "You must first call parse!" unless parse_results
      @keys = @parse_results.keys.sort unless @keys
      found_list = []
      index = 0
      args.each do |arg|
        index = find? arg, index
      end
    end
    
    # Try to match a production from the given index. Returns the end index if found 
    # or start index if not found.
    def allow? goal, index
      return NO_MATCH if index == NO_MATCH # allow users to not check results of a sequence
      found = match? goal, index
      found == NO_MATCH ? index : found
    end
    
    # Try to match a production from the given index then backtrack. Returns index if 
    # found or NO_MATCH if not.
    def check? goal, index
      return NO_MATCH if index == NO_MATCH # allow users to not check results of a sequence
      found = match? goal, index
      found == NO_MATCH ? NO_MATCH : index
    end
    
    # Try not to match a production from the given index then backtrack. Returns index 
    # if not found or NO_MATCH if found.
    def dissallow? goal, index
      return NO_MATCH if index == NO_MATCH # allow users to not check results of a sequence
      found = match? goal, index
      found == NO_MATCH ? index : NO_MATCH
    end
    
    # Special production that only matches the end of source_text. Note, this function
    # does not end in (?) or (!) because it is meant be used as a normal production.
    def eof index
      return NO_MATCH if index == NO_MATCH # allow users to not check results of a sequence
      index >= source_text.length ? index : NO_MATCH
    end
    
    # Match a production from the given index. Returns the end index if found or NO_MATCH
    # if not found.
    def match? goal, index
      return NO_MATCH if index == NO_MATCH # allow users to not check results of a sequence
      index = ignore? index unless @ignoring
      goal = goal.to_sym
      position = parse_results[index]
      found = position.fetch(goal) do
        position[goal] = IN_USE # used to prevent inifinite recursion in case user attemts 
                                # a left recursion
        _memoize goal, index, send(goal, index), position
      end
      puts "found #{goal} at #{index}...#{found} #{source_text[index...found].inspect}" if found && debug_flag
      raise "Parser cannot handle infinite (left) recursions. Please rewrite usage of '#{goal}'." if found == IN_USE
      found
    end
    
    # Record the results of the parse in the parse_results memo.
    def _memoize goal, index, result, position = parse_results[index]
      if result
        position[:found_order] = [] unless position.has_key?(:found_order)
        position[:found_order] << goal
position[goal.to_s] = source_text[index...result] if result - index < 40 && goal.is_a?(Symbol)
      end
      position[goal] = result if result || goal.is_a?(Symbol)
      result
    end

    # Match tokens that should be ignored. Used by match?(). Returns end index if found 
    # or start index if not found. Subclasses should override this method if they wish 
    # to ignore other text, such as comments.
    def ignore? index
      return NO_MATCH if index == NO_MATCH # allow users to not check results of a sequence
      return index if @ignoring || ignore_productions.nil?
      @ignoring = true
      ignore_productions.each do |prod|
        index = allow? prod, index
      end
      @ignoring = nil
      index
    end

    # Match a literal string or regular expression from the given index. Returns 
    # the end index if found or NO_MATCH if not found.
    def literal? value, index
      return NO_MATCH if index == NO_MATCH # allow users to not check results of a sequence
      case value
      when String
        string? value, index
      when Regexp
        regexp? value, index
      else
        raise "Unknown literal: #{value.inspect}"
      end
    end

    # Match a string from the given index. Returns the end index if found 
    # or NO_MATCH if not found.
    def string? value, index
      return NO_MATCH if index == NO_MATCH # allow users to not check results of a sequence
      value = value.to_s
      index = ignore? index unless @ignoring
      i2 = index + value.length
# puts source_text[index...i2].inspect + ' ' + value.inspect
      _memoize(value, index, source_text[index...i2] == value ? i2 : NO_MATCH)
    end

    # Match a regular expression from the given index. Returns the end index 
    # if found or NO_MATCH if not found.
    def regexp? value, index
      return NO_MATCH if index == NO_MATCH # allow users to not check results of a sequence
      value = correct_regexp! value
      index = ignore? index unless @ignoring
      found = value.match source_text[index..-1]
# puts "#{value.inspect} ~= #{found[0].inspect}" if found
      _memoize(value, index, found ? found.end(0) + index : NO_MATCH)
    end
    
    # Make sure regular expressions match the beginning of the string, actually from 
    # the string from the given index.
    def correct_regexp! re
      source = re.source
      source[0..1] == '\\A' ? re : Regexp.new("\\A(#{source})", re.options)
    end
    
  protected
    
    # Create an index of the parse results. Todo: unfinished.
    def index_results!
      raise "You must first call parse!" unless parse_results
      @index = new Hash {|h, k| h[k] = []}
      parse_results.each_pair do |index, prod_map|
        prod_map[:found_order].reverse_each
        prod_map.each_value
        @index[prod]
      end
    end
  end # Parser

end # Peggy
