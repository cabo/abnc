require 'parse/parser'
require 'parse/builder'
require 'parse/ast'

module Peggy

  # Implements the RFC 4234 ABNF, one of several grammars supported.
  #
  # Keep in mind, though, that the ABNF semantics is that of a BNF,
  # i.e., non-deterministic; while the packrat parser underlying peggy
  # is a PEG parser, which cuts decision points once a successful
  # parse is made.  You may have to exchange alternatives, e.g., for
  # parsing ABNF itself using ABNF, you have to change RFC 4234's rule
  #   repeat         =  1*DIGIT / (*DIGIT "*" *DIGIT)
  # into
  #   repeat         =  (*DIGIT "*" *DIGIT) / 1*DIGIT
  # as otherwise "1*(...)" will start to parse as the first
  # alternative and never try the second.

  class ABNF < Builder

    class ABNFParser < Builder

      def initialize
        super
        build
      end

    private

      def build
        self.ignore_productions = [:ws, :s]

        grammar{seq{many{prod}; eof}}
        prodname{lit /[A-Za-z][-A-Za-z0-9]*/}
        ws{lit /(?:[ \t\n]|;[^\n]*\n)+/}
        s{opt{ws}}
        prod{seq{prodname; s; lit '='; s; prodalt; s}}
        prodalt{seq{
            prodterm
            many{seq{s; lit '/'; s; prodterm}}
          }}
        prodterm{seq{
            prodatom
            many{
              seq {s; prodatom}
            }
          }}
        prodatom{
          alt {
            numlit
            casese
            seq{opt{lit "%i"}; casein}
            seq{prodname; neg{seq{s; lit '='}}}
            optgroup
            repgroup            # XXX: specific repetition is missing
            group
          }
        }
        numlit{alt{
            lit /%x[0-9A-Fa-f][0-9A-Fa-f]([-.][0-9A-Fa-f][0-9A-Fa-f])*/
            lit /%d[0-9]+([-.][0-9]+)*/
          }}
        casein{lit /"[^"]+"/} # "
        casese{lit /%s"[^"]+"/} # "
        optgroup{seq{lit "["; s; prodalt; s; lit "]"}}
        group{seq{lit "("; s; prodalt; s; lit ")"}}
        repgroup{seq{repspec; prodatom}}
        repspec{lit /[0-9]*\*[0-9]*/}
      end
    end # ABNFParser

    def compile! text, options={}
      reset!
      compiler = ABNFParser.new
# puts compiler
      # compiler.debug_flag = true
      result = compiler.parse? :grammar, text
#pp compiler.parse_results
      # raise "Invalid ABNF grammar" unless result
      grammar = compiler.ast? :ignore=>:s #options
###puts grammar
      raise "Invalid ABNF grammar at char #{compiler.parse_results.keys.max}" unless result
      grammar.each :prod do |definition|
        send(symbolize(definition.prodname.to_s)) do
          build_prodalt definition.prodalt
        end
      end
#puts to_s
    end

    private

    def symbolize name
      name = name.downcase.gsub(/-/, "_")
      if (Node.methods.include? name)
        name = "p_" + name
      end
      name.to_sym
    end

    def build_prodalt prodalt
      if prodalt._count(:prodterm) == 1
        build_prodterm prodalt.prodterm
      else
        alt do
          prodalt.each :prodterm do |prodterm|
            build_prodterm prodterm
          end
        end
      end
    end

    def build_prodterm prodterm
      if prodterm._count(:prodatom) == 1
        build_prodatom prodterm.prodatom
      else
        seq do
          prodterm.each :prodatom do |prodatom|
            build_prodatom prodatom
          end
        end
      end
    end

    def build_prodatom prodatom
      if c = prodatom.numlit
        /^%([xd])([0-9A-Fa-f]+)(.*)/ =~ c.to_s
        m = {"x" => :hex, "d" => :to_i}[$1];
        r = $2.send(m).chr
        s = $3
        if s != ''
          if s[0..0] == '.'
            r += s[1..-1].split('.').map{ |x| x.send(m).chr}.join('')
          else                  # XXX: need to barf if more than one...
            t = s[1..-1].send(m).chr
            r = /[#{r}-#{t}]/
          end
        end
        lit r
      elsif c = prodatom.casein
        lit /(?i:#{Regexp.escape(c.to_s[1..-2])})/
      elsif c = prodatom.casese
        lit /#{Regexp.escape(c.to_s[3..-2])}/
      elsif c = prodatom.prodname
        send(symbolize(c.to_s))
      elsif c = prodatom.optgroup
        opt {
          build_prodalt c.prodalt
        }
      elsif c = prodatom.repgroup
        /^([0-9]*)\*([0-9]*)/ =~ c.repspec.to_s
        minr = $1 == "" ? 0 : $1.to_i
        maxr = $2 == "" ? nil : $2.to_i
        case [minr, maxr]
        when [1, nil]
          m = :some
        when [0, nil]
          m = :many
        when [0, 1]
          m = :opt
        else             # This needs a better way to access Multiple!
          raise "repgroup -- not implemented: #{c.repspec.to_s}"
        end
        send(m) {
          build_prodatom c.prodatom
        }
      elsif c = prodatom.group
        build_prodalt c.prodalt
      else
        raise "prodatom strangeness"
      end
    end

  end #ABNF
end # Peggy
