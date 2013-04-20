#!/usr/bin/env ruby

class QueryContext < Array

  def best_concept_model
    max_sim = 0.0
    best    = nil

    for p in 0...self.count
      sim = 0.0
      for pp in 0...self.count
        next if pp == p
        combs = self.at(p).concepts.product self.at(pp).concepts
        sum_sim = combs.inject(0.0) { |sum,k| sum + k.first.weighted_concept_similarity(k.last) }
        sim += sum_sim/combs.count
      end


      if sim > max_sim
        max_sim = sim
        best = p
      end
    end
    
    best.nil? ? nil : self.at(best)
  end

  def best_concept_model_word
    max_sim = 0.0
    best    = nil

    for p in 0...self.count
      sim = 0.0
      for pp in 0...self.count
        next if pp == p
        combs = self.at(p).concepts.product self.at(pp).concepts
        sum_sim = combs.inject(0.0) { |sum,k| sum + k.first.concept_words_similarity(k.last) }
        sim += sum_sim/combs.count
      end


      if sim > max_sim
        max_sim = sim
        best = p
      end
    end
    
    best.nil? ? nil : self.at(best)
  end
end
