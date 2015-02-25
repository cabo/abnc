# Peggy packrat parser for Ruby
# 
# builder.rb - parser builder
#
# Copyright (c) 2006 Troy Heninger
#
# Peggy is copyrighted free software by Troy Heninger.
# You can redistribute it and/or modify it under the same terms as Ruby.

require 'parse/parser'

module Peggy

  # Base syntax element class.
  class Element
    # Create an element.
    def self::build *args
      new *args
    end
    
    # Test to see if there is a match of this element at the current index.
    # Return's the index following if match is found, or NO_MATCH if not
    def match parser, index
      raise "Must override match"
    end
    
    # Used for debugging.
    def report index
      # puts "#{to_s} #{index}"
      index
    end
  end
  
  # An element with a single child element.
  module OneChild
    # The single child
    attr_accessor :child
    
    # synonym for child=(element)
    alias :<< :child=
    
    # Convert to String.
    def to_s
      wrap
    end
    
    # Enclose child in parentheses if appropriate.
    def wrap
      result = child.respond_to?(:each) ? "(#{child})" : child.to_s
    end
  end

  # An element that matches a sequence of elements.  All must match for the sequence to match.
  class Sequence < Element
    # Add a child element.
    def add element
      @list = [] unless @list
      @list << element
    end

    # Synonym for add(element)
    alias :<< :add
    
    # Reference a child by index.
    def [] index
      @list[index]
    end
    
    # Child iterator.
    def each &blk
      @list.each &blk
    end
    
    # Match each child in sequence. If any fail this returns NO_MATCH. If all succeed this 
    # returns the end index of the last.
    def match parser, index
      raise "no children added to sequence" unless @list
      each do |element|
        index = element.match parser, index
        return NO_MATCH unless index
      end
      report index
    end
    
    # Convert element to String.
    def to_s
      @list.map{|el| el.to_s}.join ' '
    end
  end
  
  # An element which matches any one of its children. The children are tested in order. The first
  # to match wins.
  class Alternatives < Sequence
    # Match any one of the children. The children are tried in order. The first to match wins.
    # The result is the end index of the first matching child. If none match this returns NO_MATCH.
    def match parser, index
      raise "no children added to alternate" unless @list
      each do |element|
        found = element.match parser, index
        return report(found) if found
      end
      report NO_MATCH
    end
    
    # Convert element to String.
    def to_s
      @list.map{|el| el.to_s}.join ' | '
    end
  end
  
  # An element which tries its single child multiple times. It is greedy, meaning it will continue 
  # to match as long as possible, unless the range specifies a maximum number of matches.
  class Multiple < Element
    include OneChild
    
    # A big number
    MANY = 32767
    # The minimum and maximum number of tries
    attr_accessor :range

    # Init the range
    def initialize range
      @range = range
    end
    
    # Matches the child multiple times. The range specifies the least and most number of matches.
    # If the number of matches is less than the minimim of the range then NO_MATCH is returned.
    # If equal or more than the minimim then the end index of the last match is returned.
    def match parser, index
      raise "multiple element child not set" unless child
      raise "multiple element range not set" unless range
      count = 0
      while count < range.last
        found = child.match parser, index
        break unless found
        index = found
        count += 1
      end
      report range === count ? index : NO_MATCH
    end
    
    # Convert element to String.
    def to_s
      "#{wrap}{#{range.min}..#{range.max}}"
    end
  end
  
  # Matcher of 0 or more times.
  class AnyNumber < Multiple
    def initialize
      super 0..MANY
    end
    
    # Convert element to String.
    def to_s
      "#{wrap}*"
    end
  end
  
  # Matcher of 1 or more times.
  class AtLeastOne < Multiple
    def initialize
      super 1..MANY
    end
    
    # Convert element to String.
    def to_s
      "#{wrap}+"
    end
  end
  
  # Matcher of 0 or 1 time.
  class Optional < Multiple
    def initialize
      super 0..1
    end
    
    # Convert element to String.
    def to_s
      "#{wrap}?"
    end
  end
  
  # An element which tries its single child but does not advance the index if found.
  # Predicates control parse decisions.
  class Predicate < Element
    include OneChild
  end
    
  # Positive Predicate.
  # If found the original index is returned. If not NO_MATCH is returned.
  class Positive < Predicate
   
    # Matches the child once. If found the original index is returned.
    # If not found NO_MATCH is returned.
    def match parser, index
      raise "positive element child not set" unless child
      found = child.match parser, index
      found ? index : NO_MATCH
    end
    
    # Convert element to String.
    def to_s
      "&#{wrap}"
    end
  end
  
  # Negative Predicate.
  # If not found the original index is returned. If found NO_MATCH is returned.
  class Negative < Predicate
   
    # Matches the child once. If not found the original index is returned.
    # If found NO_MATCH is returned.
    def match parser, index
      raise "negative element child not set" unless child
      found = child.match parser, index
      found ? NO_MATCH : index
    end
    
    # Convert element to String.
    def to_s
      "!#{wrap}"
    end
  end
  
  # Match another production in the grammar.
  class Reference < Element
    # The name of the production to lookup and match.
    attr_reader :name

    # Init the name
    def initialize name=nil
      self.name = name
    end

    # Set the name of production to match.
    def name= value
      @name = value.to_sym
    end

    # Match the entire production from the parser grammar. If it matches
    # the end index is returned. If not, NO_MATCH is returned.
    def match parser, index
      raise "reference name not set" unless name
      parser.match? name, index
    end
    
    # Convert element to String.
    def to_s
      @name
    end
  end
  
  # Matcher of a grammar production. The one and only child defines the production.
  class Production < Reference
    include OneChild
    
    # The production definition.
    attr_accessor :child

    # Init the name and child.
    def initialize name=nil, child=nil
      super name
      @child = child
    end

    # Synonym of child=(element)
    alias :<< :child=
    
    # Match the production one time. If it matches the end index is returned. If not,
    # NO_MATCH is returned.
    def match parser, index
      raise "production name not set" unless name
      raise "production child not set" unless child
      report @child.match(parser, index)
    end
    
    # Convert element to String.
    def to_s
      "#{name}: #{child}"
    end
  end
  
  # Matcher of a literal string or regular expression.
  class Literal < Element
    # Value to match.
    attr_reader :value
    
    # Init the value.
    def initialize value=nil
      @value = value
    end

    # Set the value to match.
    def value= literal
      # Make sure regular expressions check at the beginnig of the string
      literal = correct_regexp literal if literal.is_a? Regexp
      @value = literal
    end
    
    # Match the literal value. If it matches the end index is returned.
    # If no, NO_MATCH is returned.
    def match parser, index
      report parser.literal?(value, index)
    end
    
    # Convert element to String.
    def to_s
      value.inspect
    end
  end

  # Parser builder. The built in methods create syntax elements. Any other
  # method called on this object create references to production, or actual
  # productions, if called at the top level.
  # Todo: Change to a class and separate from Parser.
  class Builder < Parser
    # Productions to build
    attr_reader :productions
    # Current parent being built
    attr_reader :parent
    
    # Constructor
    def initialize
      reset!
    end
    
    # Clear the parser and prepare it for a new parse.
    def reset!
      @building = true
      @productions = {}
    end

    # Reference a production by its name index.
    def [] index
      productions[index]
    end
    
    # Create a production if at the top level, or a reference to a production a 
    # production is being built.
    def method_missing name, *args
      if @building
        if @parent
          ref = Reference.new name
          @parent << ref
        elsif block_given?
          prod = Production.new name
          @parent = prod
          yield
          @parent = nil
          @productions[name] = prod
        else
          super
        end
      else
        prod = @productions[name]
# pp name.inspect, @productions.keys unless prod
        super unless prod
# puts "matching #{name} at #{args.first}"
        prod.match self, args.first
      end
    end

    # Build an Alternatives element.
    def alt &blk
      build_piece Alternatives, blk
    end
    # Synonym for alt().
    alias :one :alt
  
    # Build or match the end of file element. If currently building, a Reference to eof 
    # is built. Otherwise eof is matched. 
    def eof *args
      if @building
        method_missing :eof, *args
      else
        super args.first
      end
    end
    
    # Build a Sequence element.
    def seq &blk
      build_piece Sequence, blk
    end
    # Synonym for each()
    alias :each :seq
  
    # Add an Literal element to the parent.
    def lit *values
      if values.size == 1
        build_piece Literal, nil, values.first
      else
        one{
          for v in values
            build_piece Literal, nil, v
          end
        }
      end
    end
  
    # Build an AnyNumber element.
    def many &blk
      build_piece AnyNumber, blk
    end
  
    # Build an Optional element.
    def opt &blk
      build_piece Optional, blk
    end
  
    # Build an AtLeastOne element.
    def some &blk
      build_piece AtLeastOne, blk
    end

    # Build a negative predicate. Use when you want to make sure the enclosed element is not present.
    # The cursor is not advanced for predicates.
    def neg &blk
      build_piece Negative, blk
    end

    # Build a positive predicate. Use when you want to make sure the enclosed element is present.
    # If matched the cursor is not advanced.
    def pos &blk
      build_piece Positive, blk
    end

    # Invokes the parser from the beginning of the source on the given production goal.
    # You may provide the source here or you can set source_text prior to calling.
    # If index is provided the parser will ignore characters previous to it.
    def parse? goal, source=nil, index=0
      @building = nil
      super
    end
    
    # Convert productions to Peggy grammar. This is notable to out put any Ruby parse methods, 
    # only grammars built with Builder methods.
    def to_s
      productions.values.join "\n"
    end

  private
    
    # Add an object of klass to the parent and yield to its block. If 
    # value is specified it is passed to the klass constructor.
    def build_piece klass, blk=nil, value=nil
# puts "building #{klass.name} with #{value.inspect}"
      elem = value ? klass.new(value) : klass.new
      @parent << elem
      if blk
        parent = @parent
        @parent = elem
        blk.call
        @parent = parent
      end
    end
    
  end # Builder

end # Peggy
