#!/usr/bin/env ruby

require 'mirimiri'
require 'sanitize'
require 'lda-ruby'
require 'context/conceptual_element'
require 'context/concept_model'
require 'context/concept'
require 'context/query_context'


module Context
  @@count = Hash.new { |h,k| h[k] = {} }
  @@df    = Hash.new { |h,k| h[k] = {} }
  @@semaphore = Mutex.new

  IndexPaths = {
    :web_en        => '/mnt/disk2/ClueWeb09_English_1_sDocs',
    :web_fr        => '/mnt/disk2/ClueWeb09_French_1_sDocs',
    :web_nospam    => '/mnt/disk1/ClueWeb09_English_1noSpam',
    :robust        => '/mnt/disk5/Robust04/',
    :wt10g         => '/mnt/disk3/WT10g_index',
    :gov2          => '/mnt/disk3/GOV2_index',
    :gigaword      => '/local/data/GigaWord/index',
    :nyt           => '/local/data/NYT_index',
    :wiki_en       => '/local/data/WikiEn_index',
    :wiki_en2012   => '/local/data/WikiEn2012_index',
    :wiki_fr       => '/local/data/WikiFr_index',
    :wiki_tc2012   => '/local/data/INEXQA2012index',
    :books         => '/local/data/INEX/Books2011/indexedit',
    :ent           => '/home/sanjuan/works/nist_eval/csiro_indri.ind'
  }

  IndexPathsCaracole = {
    :web_en        => '/distant/index_clueweb/disk2/ClueWeb09_English_1_sDocs',
    :web_nospam    => '/distant/index_clueweb/disk1/ClueWeb09_English_1noSpam',
    :robust        => '/distant/data/Robust04',
    :wt10g         => '/distant/index_clueweb/disk3/WT10g_index',
    :gov2          => '/distant/index_clueweb/disk3/GOV2_index'
  }

  IndexPathsCluster = {
    :web_en        => '/local_disk/oroshi/index_clueweb/disk2/ClueWeb09_English_1_sDocs',
    :web_nospam    => '/local_disk/oroshi/index_clueweb/disk1/ClueWeb09_English_1noSpam',
    :robust        => '/local_disk/oroshi/data/Robust04',
    :wt10g         => '/local_disk/oroshi/index_clueweb/disk3/WT10g_index',
    :gov2          => '/local_disk/oroshi/index_clueweb/disk3/GOV2_index'
  }

  # #
  # From the SIGKDD 2007 paper : "Exploiting underrepresented query aspects for automatic query expansion"
  def Context.query_aspects q
    query = Mirimiri::Document.new q

    2.upto(query.words.count) do |size|
      query.ngrams(size).each do |s|
        dp = Context.count_w Context::IndexPaths[:wiki_en2012],"#1(#{s})"
        d  = Context.count_w Context::IndexPaths[:wiki_en2012],"#{s}",100000000 
        p s

        denum = s.split.permutation.inject(0.0) do |res,p|
          tmp = (p == s.split) ? 0 : Context.count_w(Context::IndexPaths[:wiki_en2012],"#1(#{p.join(" ")})")
          res + tmp
        end

        existence = dp.to_f/d
        support = dp.to_f/denum
        puts "#{s} ===> #{existence*support}"
      end
    end
  end

  # #
  # From the CIKM 2007 paper : "Ranking Very Many Typed Entities on Wikipedia"
  #
  # The ``entities`` parameter is currently an array of strings. Could be moved
  # to an array of Entity objects.
  def Context.entity_web_ranking query,entities,nbdocs=100,index='web_nospam'
    q = Indri::IndriQuery.new({:query => "#combine ( #{query} )", :count => nbdocs},"-trecFormat=true")
    indri_index = Indri::IndriIndex.new IndexPaths[index.to_sym]
    docs = indri_index.runquery(q).force_encoding("ISO-8859-1").encode("UTF-8")
    query_list = docs.split("\n").collect { |p| p.scan(/\d+ Q0 (.+) \d+ -\d+.\d+ .+/).first }.flatten

    res = entities.pmap(15) do |e|
      eq = Indri::IndriQuery.new({:query => "#combine ( #{e.gsub(/[^a-zA-Z0-9\s]/,'')} )", :count => nbdocs},"-trecFormat=true")
      edocs = indri_index.runquery(eq).force_encoding("ISO-8859-1").encode("UTF-8") 
      e_list = edocs.split("\n").collect { |p| p.scan(/\d+ Q0 (.+) \d+ -\d+.\d+ .+/).first }.flatten

      rels = e_list&query_list

      ave_p = 1.upto(nbdocs).inject(0.0) do |sum,k| 
        p = (e_list.first(k)&rels).count.to_f/k
        rel = rels.include?(e_list[k-1]) ? 1.0 : 0.0
        sum + p*rel
      end

      {:name => e, :score => ave_p}
    end

    res.sort { |a,b| b[:score] <=> a[:score] }
  end

  def Context.query_entities query,nb_docs=10
    sources = ['wiki_en2012']
#    sources = ['wiki_en2012','web_nospam','nyt','gigaword']
#    sources = ['web_fr']
    sc = Hash.new { |h,k| h[k] = 0.0 }

    sources.each do |source|
      puts " == source : #{source}"
      c = ConceptModel.new query,source,nb_docs
      p c.query

      c.concepts.each do |concept|
        querys = concept.words[0,4].join " "

        d1 = Context::label_candidate querys.sequential_dependence_model,'wiki_en'
        d2 = Context::label_candidate querys.sequential_dependence_model,'wiki_en2012'
        d3 = Mirimiri::WikipediaPage.search_wikipedia_titles querys

        d1 = [] if d1.nil?
        d2 = [] if d2.nil?
        d3 = [] if d3.nil?

        d =  d2 & d3
        labels = d.collect { |c| c.downcase.gsub(/[^\w\d]/,' ') }
        p d


        mins = -10000000
        lab = nil
        scores = labels.collect do |l|
          s = concept.score_label l 
          if s > mins
            mins = s
            lab = l
          end
          sc[l] += s*(concept.coherence/c.total_coherence)
          { :label => l, :score => s }
        end

        print (concept.coherence/c.total_coherence).to_s+" <= "
        p concept.elements.collect { |c| c.word }
      end
    end

    sc.sort { |a,b| b[1] <=> a[1] }
  end

  def Context.label_candidate query,index,nb_candidates,rm3=false
#    Mirimiri::WikipediaPage.search_wikipedia_titles query  
    args = rm3 ? "-fbDocs=20 -fbTerms=30 -fbMu=2000 -fbOrigWeight=0.7" : ""
    q = Indri::IndriQuery.new({:query => query, :count => nb_candidates},"-printDocuments=true -trecFormat=true #{args}")
    index = Indri::IndriIndex.new IndexPaths[index.to_sym]
    docs = index.runquery q
    docs = docs.force_encoding("ISO-8859-1").encode("UTF-8") if ['web_fr','web_en','web_nospam'].include? index
    idocs = Indri::IndriPrintedDocuments.new(docs)

    wiki_titles = idocs.extract_docs.collect do |d|
      t = Nokogiri::HTML d
      t.xpath('//title').text
    end

    wiki_titles
  end

  def Context.lcm query
    source = 'nyt'

    a = Time.now
    qc = QueryContext.new(1.upto(20).collect do |nb_docs|
      beg = Time.now
      c = ConceptModel.new query,source,nb_docs
      puts "#{nb_docs} ==> Time elapsed: #{Time.now-beg} seconds" 
      c
    end)
    puts "All concepts : #{Time.now-a} seconds"

    model = qc.best_concept_model
    puts "Total : #{Time.now-a} seconds"
    model
  end

  def Context.term_context index_path,query,size,num_page,args={}
    terms    = self.term_concepts index_path,query,size,num_page,args
    args[:window] ||= 1

#    context = "#weight ( #{terms.compact.sort{ |a,b| b[0] <=> a[0]}[0,size].collect { |e| "#{e[0]} #1(#{e[1]})" }.join " "} ) " unless terms.empty?
    context = "#weight ( #{terms.collect { |c| "#{"%.10f" % c[:score]} #uw#{args[:window]}(#{c[:concept]})" }.join " "} ) " unless terms.empty?

    context
  end

# From SIGIR'06 paper : `Improving the estimation of relevance models using large external corpora`
#
  def Context.morm index_path,query,size,num_page
    docs,scores,names = self.feedback_docs  index_path,query,num_page

    terms = []

    docs.each do |d|
      r = Mirimiri::Document.new d
      tmp = self.extract_ngrams r,:tf,1
      terms += tmp.compact.collect { |t| [t[0]*Math.exp(scores[docs.index(d)].to_f),t[1]] }
    end

    final = terms.compact.sort{ |a,b| b[0] <=> a[0]}[0,size].collect { |e| { :score => e[0], :concept => e[1] } }
    context = "#weight ( #{final.collect { |c| "#{"%.10f" % c[:score]} #1(#{c[:concept]})" }.join " "} ) " unless terms.empty?

    context
  end

  def Context.term_concepts index_path,query,size,num_page,args={}
    args[:func]   ||= :entropy
    args[:window] ||= 1

    docs     = self.feedback_docs  index_path,query,num_page

    resource = Mirimiri::Document.new docs.join(' ')
    terms    = self.extract_ngrams resource,args[:func].to_sym,args[:window]

    terms.compact.sort{ |a,b| b[0] <=> a[0]}[0,size].collect { |e| { :score => e[0], :concept => e[1] } }
  end


  def Context.sentence_similarity s1,s2,index_path
    q = s1.is_a?(String) ? s1.split : s1
    r = s2.is_a?(String) ? s2.split : s2

    inter = q & r

    s = (inter.count/q.count.to_f) * inter.inject(0.0) { |sum,w| sum + Math.log(Context.df index_path,w) }
    s
  end


  private

  def Context.df index_path,w,window=1
    if @@count[index_path]["total#{window}"].nil?
      total = `dumpindex #{index_path} s`.match(/total terms:\t(.*)/)[1].to_f-(window-1).to_f
      @@semaphore.synchronize {
        @@count[index_path]["total#{window}"] = total
      }
    end

    if @@df[index_path]["#uw#{window}(#{w})"].nil?
      nb = `dumpindex #{index_path} e "#uw#{window}(#{w})" | awk ' { arr[$1]=$0 } END { for ( key in arr ) { print arr[key] } } ' | wc -l`.chomp.split(':').last.to_f - 1
      @@semaphore.synchronize {
        @@df[index_path]["#uw#{window}(#{w})"] = nb+1.0 
      }
    end
    begin
    d = @@count[index_path]["total#{window}"]/@@df[index_path]["#uw#{window}(#{w})"]
    rescue
      puts w
    exit
    end
    d
  end

  def Context.prob_w index_path,w,window=1
    if @@count[index_path]["total#{window}"].nil?
      total = `dumpindex #{index_path} s`.match(/total terms:\t(.*)/)[1].to_f-(window-1).to_f
      @@semaphore.synchronize {
        @@count[index_path]["total#{window}"] = total+1.0
      }
    end

    nb = self.count_w index_path,w,window
    nb/@@count[index_path]["total#{window}"]
  end

  def Context.count_w index_path,w,window=1
    if @@count[index_path]["##{window}(#{w})"].nil?
      nb = `dumpindex #{index_path} x "##{window}(#{w})"`.chomp.split(':').last.to_f 
      @@semaphore.synchronize {
        @@count[index_path]["##{window}(#{w})"] = ("%.15f" % nb).to_f+1.0
      }
    end
    @@count[index_path]["##{window}(#{w})"]
  end


  public
  def Context.extract_ngrams resource,func,n
    raw_terms = 1.upto(n).collect      { |i| resource.ngrams(i) }.flatten
#    raw_terms = resource.ngrams(n).flatten
    terms     = raw_terms.uniq.collect { |w| [resource.send(func.to_sym,w), w.unaccent] unless w.is_stopword? || w.split.any? { |e| e.length <= 2 } || w.split.any? { |e| e !~ /[a-zA-Z]/ } || w.include?(".") || (Mirimiri::Stoplist&w.unaccent.split).count >= 2 }
#    terms     = raw_terms.uniq.collect { |w| w=w.gsub(/\W/,' ').strip; [resource.send(func.to_sym,w), w.unaccent] unless w.is_stopword? || w.split.any? { |e| e.length <= 2 } || w.split.any? { |e| e !~ /[a-zA-Z]/ } || w.include?(".") || (Mirimiri::Stoplist&w.unaccent.split).count >= 1 }
#    terms     = raw_terms.uniq.collect { |w| [resource.send(func.to_sym,w), w.unaccent] unless w.is_stopword? || w.split.all? { |e| e.length <= 1 } || w.split.all? { |e| e !~ /[a-zA-Z]/ } || w.include?(".") }
    terms
  end

  def Context.feedback_docs index_path,query,num_page
    query = Indri::IndriQuery.new({:query => query, :count => num_page},"-printDocuments=true -trecFormat=true")
    index = Indri::IndriIndex.new index_path
    idocs = Indri::IndriPrintedDocuments.new(index.runquery(query).force_encoding("ISO-8859-1").encode("UTF-8"))

    texts,scores,names = idocs.extract_docs_score

    docs = texts.collect do |idoc| 
      begin
        Sanitize.clean idoc,:remove_contents => ['script','style']
      rescue
        d = Nokogiri::HTML(idoc)
        d.xpath('//text()').text
      end
    end

    return docs,scores,names
  end

end
