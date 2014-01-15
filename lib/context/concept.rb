#!/usr/bin/env ruby

class Concept
  attr_reader :elements, :coherence
  
  def initialize
    @elements = []
    @coherence = 0
  end

  def <<(elem)
    raise ArgumentError, 'Argument must be a ConceptualElement.' unless elem.is_a? ConceptualElement
    @elements << elem
  end

  def compute_coherence scores,theta,k#arg=nil
#    update_feedback_coherence arg
    @coherence = 0.upto(theta.count-1).inject(0.0) do |sum,i|
      sum + Math.exp(theta[i][k])*Math.exp(scores[i].to_f)
    end
  end

  def score_label label,index_path=Context::IndexPaths[:wiki_en2012]
    s = @elements.inject(0.0) do |res,e|
#      *self.prob_w(index_path,"#{w[:word]} #uw10(#{label})")
      res + e.prob*Math.log(Context.prob_w(index_path,"#{e.word} #uw10(#{label})")/(e.p_in_coll*Context.prob_w(index_path,label)))
    end

    s
  end

  def concept_words_similarity s,index_path=Context::IndexPaths[:wiki_en]
#    inter = @elements.collect { |w| w unless (w.word & s).empty? }
    inter = self.words & s.words

    sim = (inter.count/self.words.count.to_f) * inter.inject(0.0) { |sum,w| sum + Math.log(Context.df index_path,w) }
    sim
  end

  def weighted_concept_similarity s,index_path=Context::IndexPaths[:wiki_en]
    inter = self.words & s.words
    sim = (inter.count/self.words.count.to_f)
    sim *= @elements.inject(0.0) do |sum,w|
      wp = s.get_element_from_word w.word

      s.words.include?(w.word) ? sum + wp.prob*w.prob*Math.log(Context.df index_path,w.word) : sum + 0.0
    end
    sim
  end

  def get_element_from_word w
    @elements.select { |e| e.word == w }.first
  end

  def words
    @elements.collect { |w| w.word }
  end

  def word_probs
    res = {}
    @elements.each { |w| res[w.word] = w.prob }
    res
  end

# From papers :
#  NAACL'10: `Automatic Evaluation of Topic Coherence`
#  EMNLP'12: `Exploring Topic Coherence over many models and many topics`
#
  def uci_coherence index_path,epsilon=1
    coherence = @elements.combination(2).inject(0.0) do |res,bigram|
#Context.prob_w(index_path,"#{bigram.first.word} #{bigram.last.word}",20)*
      w1 = bigram.first.word.gsub(/-$/,'')
      w2 = bigram.last.word.gsub(/-$/,'')
      t = (Context.prob_w(index_path,"#{w1} #{w2}",20)+epsilon)/((bigram.first.p_in_coll index_path)*(bigram.last.p_in_coll index_path))
      res + Math.log(t)
    end

    coherence /= @elements.count*(@elements.count-1)
    coherence
  end

  def uci_coherence_entropy index_path=Context::IndexPaths[:wiki_en]
    coherence = @elements.combination(2).inject(0.0) do |res,bigram|
#Context.prob_w(index_path,"#{bigram.first.word} #{bigram.last.word}",20)*
      t = (Context.prob_w(index_path,"#{bigram.first.word} #{bigram.last.word}",20))/((bigram.first.p_in_coll)*(bigram.last.p_in_coll))
      res + t
    end

    coherence /= @elements.count*(@elements.count-1)
    coherence
  end

  protected
  def update_coherence index_path=Context::IndexPaths[:wiki_en]
    coherence = @elements.combination(2).inject(0.0) do |res,bigram|
      res + Context.prob_w(index_path,"#{bigram.first.word} #{bigram.last.word}")*Math.log(Context.prob_w(index_path,"#{bigram.first.word} #{bigram.last.word}")/((bigram.first.p_in_coll index_path)*(bigram.last.p_in_coll index_path)))
    end

    coherence /= @elements.count*(@elements.count-1)
    @coherence = coherence
  end

  def update_feedback_coherence documents 
    corpus = Mirimiri::Document.new documents.join " "

    windows = corpus.ngrams(10).collect { |w| w.split }

    coherence = @elements.combination(2).inject(0.0) do |res,bigram|
      big_prob = windows.count{ |c| c.include?(bigram.first.word) && c.include?(bigram.last.word) }.to_f/windows.count
      mi = big_prob.zero? ? 0.0 : big_prob*bigram.first.prob*bigram.last.prob*Math.log(big_prob/(corpus.tf(bigram.first.word)*corpus.tf(bigram.last.word)))
      res + mi
    end 

    coherence /= @elements.count*(@elements.count-1)
    @coherence = coherence
  end

end
