# Peggy packrat parster for Ruby
# 
# ast.rb - Abstract Syntax Tree
#
# Copyright (c) 2006 Troy Heninger
#
# Peggy is copyrighted free software by Troy Heninger.
# You can redistribute it and/or modify it under the same terms as Ruby.

module Peggy

  # A node in an Abstract Syntax Tree. Every node in the tree maps to a production 
  # found in the parse. You can navigate to the node's parent, first child, or next 
  # sibling. Nodes know their range of the source text.
  class Node
    include Enumerable
  
    attr_accessor :_name, :_first, :_next, :_parent, :_range, :_source
    
    # Constructor
    def initialize name
      self._name = name
    end
    
    # Add a child.
    def << child
      child._parent = self
#puts "#{_name}[first #{_first} last #{_last}] << child #{child._name}"
      if _first
        _last._next = child
      else
        self._first = child
      end
    end
    
    # Iterate over each child. If name is supplied only nodes matching the name are iterated.
    def each name=nil
      child = _first
      while child
        yield child if name.nil? || name == child._name
        child = child._next
      end
    end

    def children name=nil
      a = []
      each(name) do |node|
        a << node
      end
      a
    end

    # Count the children. If name is supplied only nodes matching the name are counted.
    def _count name=nil
      c = 0
      each do |node|
        c += 1 if name.nil? || name == node._name
      end
      c
    end
    
    # Get the number of nodes up to the root.
    def _depth
      depth = 0
      node = self
      depth += 1 while node=node._parent
      depth
    end
    
    # Get the root node.
    def _root
      node = self
      while (n2 = node._parent)
        node = n2
      end
      node
    end
    
    # Get an option set when tree was created.
    def _option option, default=nil
      options = _root._options
      return nil unless options
      options[option] || options[option.to_sym] || default
    end
    
    # Get the length of the range.
    def _length
      _range.last - _range.first
    end

    # Get some or all of the source text covered by this node, depending on the length.
    def _sample
      return nil if _length == 0
      str = _source[_range]
      (str.length >= 40 ? str[0, 37] + '...' : str).inspect
    end
    
    # Format the node pretty printing.
    def _format
      result = "#{'  '*_depth}#{_name} #{_sample}\n"
      each do |node|
        result << node._format
      end
      result
    end
    
    # Get the last child.
    def _last
      node = _first
      return nil unless node
      while (n2 = node._next)
        node = n2
      end
      node
    end
    
    # Get the contents for inspection.
    def inspect
      "#{_name ? _name : self.class}[#{_range}] #{to_s.inspect}"
    end
    
    # Get the source text minus any ignored nodes.
    def _strip
      return @str if @str
      str0 = str = _source[_range]
      return @str = str unless (ignore = _option :ignore) && _first
      remove = find_all{|node| node._name == ignore}
      remove.reverse_each do |node|
        from = node._range.first - _range.first
        str = str[0, from] + str[from + node._length..-1]
      end
# puts "before #{str0.inspect}, after #{str.inspect}" unless remove.empty?
      @str = str
    end
    
    # Get the source text covered by this node.
    def to_s
      _source[_range]
    end
    
    # Get the stripped text as a Symbol.
    def to_sym
      _strip.to_sym
    end
    
    # Get the first node of the given name as a Symbol.
    def [] name
      method_missing name.to_sym
    end

    def method_missing name, *args
      find {|node| name == node._name}
    end

  end
  
  # The root node of an Abstract Syntax Tree. Every node in the tree maps to a production 
  # found in the parse.
  class AST < Node
  
    attr_reader :_options
    
    def initialize source, results, options={}
      super nil
      @results = results
      @_options = options
      @ignore = Array(options[:ignore]) # XXX: turn to set
      self._source = source
      build_left nil, 0, self
    end

    def to_s
      _format
    end
    
  private

    def build_left parent, index, node=nil
      result = parent ? parent._range.last : index
      row = @results[index]
      return result unless row
      order = row[:found_order]
      return result unless order
      order.reverse_each do |name|
        continue if @ignore.include? name
        to = row[name]
        if node
          node._name = name
        else
          node = Node.new name
        end
        node._range = index...to
        node._source = _source
#puts "Built #{node.to_s}"
        parent << node if parent
        build_children parent, to if parent && to > index && to < parent._range.last
        parent = node
        node = nil
      end
      result
    end

    def build_children parent, index
      while index < parent._range.last
        i2 = build_left parent, index
        break if i2 <= index
        index = i2
      end
    end

  end
  
  class Parser

    # Create an Abstract Syntax Tree from the parse results. You must call parse?() prior to
    # this. Valid options:
    # * :ignore=>[symbol of element to ignore]
    def ast? options={}
      ast = AST.new source_text, parse_results, options
#puts ast
      ast
    end

  end

end # Peggy
