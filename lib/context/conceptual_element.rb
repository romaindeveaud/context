#!/usr/bin/env ruby

class ConceptualElement
  attr_reader :word, :prob

  def initialize w,s  
    raise ArgumentError, 'Argument 1 must be a String.' unless w.is_a? String
    raise ArgumentError, 'Argument 2 must be a Float.'  unless s.is_a? Float

    tmp = w.gsub(/(-)\1+/,'-').gsub(/([^\w-].*|^-|-$)/,'')
    raise ArgumentError, 'Arguments 1 is not a useful word ! ;)' if tmp.is_stopword? || tmp.size < 2

    @word = tmp
    @prob = s
  end

  def p_in_coll index_path=Context::IndexPaths[:wiki_en],size=20
    Context.prob_w index_path,@word.gsub(/-$/,''),size
  end
end
