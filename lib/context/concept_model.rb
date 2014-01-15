#!/usr/bin/env ruby

require 'lda-ruby'
require 'peach'

class ConceptModel
  attr_reader :concepts,:documents,:source,:nbdocs,:nbterms,:query,:total_coherence,:doc_scores,:doc_names,:theta,:entropy_coherence,:avg_coherence,:avg_query_coherence

  def ConceptModel.parse_hdp str
    concepts = []
    eval(str).each do |hdp_top|
      c = Concept.new
      hdp_top.gsub(/topic \d: /,'').split(" + ").each do |words|
        ee = words.split('*') 
        begin
          e = ConceptualElement.new ee[1],ee[0].to_f
          c << e 
        rescue ArgumentError
          next
        end
      end

      concepts << c
    end
    concepts
  end

  def initialize query,source,nb_docs,nb_terms=10,k=false
    raise ArgumentError, 'Argument 1 must be a String.' unless query.is_a? String
    raise ArgumentError, 'Argument 2 must be a valid Index key.' unless Context::IndexPaths.has_key?(source.to_sym)

    @source  = source.to_sym
    @nbdocs  = nb_docs
    @nbterms = nb_terms
    @query   = query
    @concepts = []
    @total_coherence = 0.0

    corpus = Lda::Corpus.new

    @documents,@doc_scores,@doc_names = Context.feedback_docs Context::IndexPaths[@source],@query,@nbdocs

    @documents.each do |d|
      doc = Lda::TextDocument.new corpus,d
      corpus.add_document doc
    end

    if k == false
      num_topics = topic_divergence corpus
    else
      num_topics = k
    end

    lda = Lda::Lda.new corpus
    lda.verbose=false
    lda.num_topics = num_topics

    lda.em('random')

    @beta  = lda.beta   # to avoid repeated expensive computation
    @vocab  = lda.vocab  #

    @theta = lda.compute_topic_document_probability

# Normalizing the phi_t(w) weights for each topic
#
    total_prob = {}
    tmp_top_word_indices(@nbterms,@vocab,@beta).each_pair do |topic,indices|
      total_prob[topic] = indices.inject(0.0) { |res,i| res + Math.exp(@beta[topic][i].to_f) }
    end

    tmp_top_word_indices(@nbterms,@vocab,@beta).each_pair do |topic,indices|
      c = Concept.new
      indices.each do |i| 
        begin
          e = ConceptualElement.new @vocab[i],(Math.exp(@beta[topic][i].to_f)/total_prob[topic])
          c << e
        rescue ArgumentError
          next
        end
      end

      c.compute_coherence @doc_scores,@theta,topic

#      c.compute_coherence @doc_scores,gamma_m,topic # takes time since it has to compute several probabilities
      @concepts << c
      @total_coherence += c.coherence
    end
  end

  def model_divergence
    topics_i = Array.new(@concepts.count) { |i| i }

    sum_kl = topics_i.combination(2).inject(0.0) do |kl,topics|
      ti = topics.first
      tj = topics.last
      begin
        kl + 0.upto(@vocab.count-1).inject(0.0) do |res,w_i| 
          res + ( Math.exp(@beta[ti][w_i])*Math.log(Math.exp(@beta[ti][w_i])/Math.exp(@beta[tj][w_i])) ) #+ Math.exp(@beta[tj][w_i])*Math.log(Math.exp(@beta[tj][w_i])/Math.exp(@beta[ti][w_i])) )
        end
      rescue
        kl + 0.0
      end
    end

    sum_kl /= @concepts.count*(@concepts.count-1)
#    sum_kl = max_kl if sum_kl.nan? || sum_kl.infinite? 

    sum_kl
  end

  def to_s
    @concepts.collect do |c|
      "#{c.coherence/@total_coherence} => [#{c.elements.collect do |e|
        "#{e.prob} #{e.word}"
      end.join(', ')
      }]"
    end.join "\n"
  end

  def to_indriq
    "#weight( #{@concepts.collect do |c|
      "#{c.coherence/@total_coherence} #weight ( #{c.elements.collect do |e|
        "#{e.prob} #{e.word}"
      end.join(' ')
      } ) "
    end.join " "} )"
  end

  def <<(concept)
    raise ArgumentError, 'Argument must be a Concept.' unless elem.is_a? Concept
    @concepts << concept
  end

  def avg_model_coherence index_path=Context::IndexPaths[:wiki_en]
    if @documents.empty?
      @avg_coherence = 0.0 
    else
      @avg_coherence = @concepts.inject(0.0) { |res,c| res + c.uci_coherence(index_path) }/@concepts.count #if @avg_coherence.nil?
    end
    @avg_coherence
  end

  def avg_model_query_coherence index_path=Context::IndexPaths[:wiki_en]
    if @documents.empty?
      @avg_query_coherence = 0.0 
    else
      @avg_query_coherence = @concepts.inject(0.0) { |res,c| res + c.coherence*c.uci_coherence(index_path) }/@concepts.count #if @avg_coherence.nil?
    end
    @avg_query_coherence
  end

  def entropy_model_coherence
    if @documents.empty?
      @entropy_coherence = 0.0 
    else  
      @entropy_coherence = @concepts.inject(0.0) do |res,c| 
        ent = c.uci_coherence_entropy
        ent += 0.0000000000000000000000001 if ent.zero?
        res + ent*Math.log(ent)
      end #if @entropy_coherence.nil?
    end
    @entropy_coherence
  end

  private
  def topic_divergence corpus
    max_kl = 0.0
# Old trick to limit number of iterations
#    num_p = @nbdocs < 6 ? @nbdocs + 5 : @nbdocs 

    semaphore = Mutex.new

    1.upto(20).inject do |k,ntop|
#    1.upto(num_p).inject do |k,ntop|
      lda = Lda::Lda.new corpus
      lda.verbose=false
      lda.num_topics = ntop
      lda.em('random')
      beta_m = lda.beta   # to avoid repeated expensive computation
      vocab  = lda.vocab

      topics_i = Array.new(ntop) { |i| i }

      sum_kl = topics_i.combination(2).inject(0.0) do |kl,topics|
        ti = topics.first
        tj = topics.last
        begin
          kl + 0.upto(vocab.count-1).inject(0.0) do |res,w_i| 
            res + ( Math.exp(beta_m[ti][w_i])*Math.log(Math.exp(beta_m[ti][w_i])/Math.exp(beta_m[tj][w_i])) + Math.exp(beta_m[tj][w_i])*Math.log(Math.exp(beta_m[tj][w_i])/Math.exp(beta_m[ti][w_i])) )
          end
        rescue
          kl + 0.0
        end
      end

      sum_kl /= ntop*(ntop-1)
      sum_kl = max_kl if sum_kl.nan? || sum_kl.infinite? 

      sum_kl <= max_kl ? k : (max_kl = sum_kl and ntop)
    end
  end

  def tmp_top_word_indices(words_per_topic = 10,vocab,beta)
    raise 'No vocabulary loaded.' unless vocab

    # find the highest scoring words per topic
    topics = Hash.new
    indices = (0...vocab.size).to_a

    beta.each_with_index do |topic, topic_num|
      topics[topic_num] = (topic.zip((0...vocab.size).to_a).sort { |i, j| i[0] <=> j[0] }.map { |i, j| j }.reverse)[0...words_per_topic]
    end

    topics
  end

end
