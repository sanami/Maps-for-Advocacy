class Disability < ActiveRecord::Base
	translates :name

	has_many :disability_translations, :dependent => :destroy
	has_many :place_evalations
  has_and_belongs_to_many :question_pairings
  accepts_nested_attributes_for :disability_translations
  attr_accessible :code, :disability_translations_attributes
  
  validates :code, :presence => true

  # sort by name
  def self.sorted
    with_translations(I18n.locale).order('disability_translations.name asc')
  end

  # get a disability and include the name
  def self.with_name(id)
    with_translations(I18n.locale).find(id)
  end


  # get number of places with evaluations for each disability
  def self.names_with_count(options={})
    sql = "select d.id, dt.name as disability, count(x.id) as `count`  "
    sql << "from disabilities as d  "
    sql << "inner join disability_translations as dt on dt.disability_id = d.id " 
    sql << "left join (  "
    sql << " select d.id, pe.place_id "
    sql << " from disabilities as d inner join place_evaluations as pe on pe.disability_id = d.id  "
    if options[:venue_category_id].present?
      sql << " inner join places as p on p.id = pe.place_id "
      sql << " inner join venues as v on v.id = p.venue_id and v.venue_category_id = :venue_category_id "
    end
    sql << " group by d.id, pe.place_id  "
    sql << ") as x on x.id = d.id " 
    sql << "where dt.locale = :locale "
    sql << "group by d.id, dt.name "
    sql << "order by dt.name "
    find_by_sql([sql, :locale => I18n.locale, :venue_category_id => options[:venue_category_id]])
  end
  

end