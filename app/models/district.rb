class District < ActiveRecord::Base
	translates :name

	has_many :district_translations, :dependent => :destroy
	has_many :places
  accepts_nested_attributes_for :district_translations
  attr_accessible :id, :json, :district_translations_attributes, :in_tbilisi
  validates :json, :presence => true
  
  TBILISI_ID = 999
  
  def self.no_json
    select('districts.id, district_translations.name as district_name')
    .joins(:district_translations)
    .where('district_translations.locale = ?', I18n.locale)
    .order('districts.id')
  end


  # get number of places with evaluations for each district
  def self.names_with_count(options={})
    need_and = false
    sql = "select d.id, dt.name as district, d.in_tbilisi, count(x.id) as `count`  "
    sql << "from districts as d  "
    sql << "inner join district_translations as dt on dt.district_id = d.id " 
    sql << "inner join ( "
    sql << " select d.id, p.id as place_id "
    sql << " from districts as d inner join places as p on p.district_id = d.id  "
    if options[:disability_id].present? || options[:places_with_evaluation] == true
      sql << " inner join place_evaluations as pe on pe.place_id = p.id "
      if options[:disability_id].present?
        sql << " and pe.disability_id = :disability_id "
      end
    end
    if options[:venue_category_id].present?
      sql << " inner join venues as v on v.id = p.venue_id and v.venue_category_id = :venue_category_id "
    end
    if options[:place_search].present? || options[:address_search].present?
      sql << " inner join place_translations as pt on pt.place_id = p.id "
      sql << " where "
    end
    if options[:place_search].present?
      sql << " pt.locale = :locale and pt.search_name like :place_search "
      need_and = true
    end
    if options[:address_search].present?
      if need_and
        sql << " and "
      end
      sql << " pt.search_address like :address_search "
    end
    sql << " group by d.id, p.id  "
    sql << ") as x on x.id = d.id " 
    sql << "where dt.locale = :locale "
    sql << "group by d.id, dt.name "
    sql << "order by dt.name "
    x = find_by_sql([sql, :locale => I18n.locale, :venue_category_id => options[:venue_category_id], :disability_id => options[:disability_id], 
      :place_search => "%#{options[:place_search]}%", :address_search => "%#{options[:address_search]}%"])
    
    # update the custom tbilisi district to include the counts from all districts in tbilisi 
    tbilisi = x.select{|x| x.id == TBILISI_ID}
    if tbilisi.present?
      tbilisi.first['count'] += x.select{|x| x.in_tbilisi == true}.map{|x| x['count']}.sum
    end
    
    # return only records with counts > 0
    if options[:places_with_evaluation] == true
      return x.select{|x| x['count'] > 0}
    else
      return x
    end
  end
  

  

  #######################################
  ## load districts from json file
  #######################################
  def self.process_json_upload(file, delete_first=false)
		start = Time.now
    json = file.read
    n, msg = 0, ""
    idx_id = 0
    idx_name = 1
    idx_json = 2

		original_locale = I18n.locale
    I18n.locale = :en

		District.transaction do
		  if delete_first
        puts "******** deleting all districts on record first"
        # quicker to do delete all instead of destroy        
        District.delete_all
        DistrictTranslation.delete_all
		  end
		
      # convert json to hash
      hash = JSON.parse(json)
      
      hash['features'].each_with_index do |feature, index|
        puts "@@@@@@@@@@@@@@@@@@ processing item #{index}"
        id = feature['properties']['District_c']
        name = feature['properties']['District_n']
        geo = feature['geometry']
        if id.present? && name.present? && geo.present?
          # only add if district has id
          if id.to_i > 0
            d = District.create(:id => id.to_i, :json => geo.to_json)
            I18n.available_locales.each do |locale|
              d.district_translations.create(:locale => locale, :name => name.strip)
            end
          end
        else
    		  msg = "Item #{index}: Required data is missing"
	        raise ActiveRecord::Rollback
    		  return msg
        end
      end

    end
  	puts "****************** time to build_from_csv: #{Time.now-start} seconds"

		# reset the locale
		I18n.locale = original_locale

    return msg

  end
  
  #######################################
  ## load districts from csv file
  #######################################
  def self.process_csv_upload(file, delete_first=false)
		start = Time.now
    infile = file.read
    n, msg = 0, ""
    idx_id = 0
    idx_name = 1
    idx_json = 2

		original_locale = I18n.locale
    I18n.locale = :en

		District.transaction do
		  if delete_first
        puts "******** deleting all districts on record first"
        # quicker to do delete all instead of destroy        
        District.delete_all
        DistrictTranslation.delete_all
		  end
		
		
		  CSV.parse(infile, :col_sep => "\t") do |row|
        startRow = Time.now
		    n += 1
        puts "@@@@@@@@@@@@@@@@@@ processing row #{n}"

        # must have all 3 values to save
        if row[idx_id].present? && row[idx_name].present? && row[idx_json].present?
          d = District.create(:id => row[idx_id], :json => row[idx_json].strip)
          I18n.available_locales.each do |locale|
            d.district_translations.create(:locale => locale, :name => row[idx_name].strip)
          end
        else
    		  msg = "Row #{n}: Required data is missing"
	        raise ActiveRecord::Rollback
    		  return msg
        end
      end
    end
  	puts "****************** time to build_from_csv: #{Time.now-start} seconds"

		# reset the locale
		I18n.locale = original_locale

    return msg

  end  
  
  #######################################
  ## load georgian district names from csv file
  #######################################
  def self.process_georgian_name_csv_upload(file)
		start = Time.now
    infile = file.read
    n, msg = 0, ""
    idx_id = 0
    idx_name = 1

		original_locale = I18n.locale
    I18n.locale = :en

		District.transaction do
		  CSV.parse(infile) do |row|
        startRow = Time.now
		    n += 1
        puts "@@@@@@@@@@@@@@@@@@ processing row #{n}"

        # must have all 2 values to save
        if row[idx_id].present? && row[idx_name].present?
          DistrictTranslation.where(:district_id => row[idx_id], :locale => 'ka').update_all(:name => row[idx_name].strip)
        else
    		  msg = "Row #{n}: Required data is missing"
	        raise ActiveRecord::Rollback
    		  return msg
        end
      end
    end
  	puts "****************** time to build_from_csv: #{Time.now-start} seconds"

		# reset the locale
		I18n.locale = original_locale

    return msg

  end    
end
