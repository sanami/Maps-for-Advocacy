# encoding: UTF-8
class QuestionCategory < ActiveRecord::Base
	translates :name
  has_ancestry

  has_one :venue
	has_many :question_category_translations, :dependent => :destroy
	has_many :question_pairings, :dependent => :destroy
	has_many :questions, :through => :question_pairings
	has_many :venue_question_categories, :dependent => :destroy
  accepts_nested_attributes_for :question_category_translations
  accepts_nested_attributes_for :question_pairings
  attr_accessible :id, :is_common, :question_category_translations_attributes, :question_pairings_attributes, 
                  :sort_order, :category_type, :unique_id

  before_save :set_sort_order
  DEFAULT_SORT_ORDER = 99
  TYPES = {'common' => 1, 'custom' => 2, 'public' => 3, 'public_custom' => 4}

  
  def set_sort_order
    self.sort_order = DEFAULT_SORT_ORDER if read_attribute(:sort_order).blank?
  end

  def is_certified?
    self.category_type == TYPES['common'] || self.category_type == TYPES['custom']
  end


  # possible options: category_type, child_of, question_category_id, disability_id
  def self.with_questions(options = {})
    categories = nil

    categories = get_categories(options)

    if categories.present?
    
      categories.each do |cat|
        # get the questions for this category
        new_options = {}
        new_options[:disability_id] = options[:disability_id] if options[:disability_id].present?
        new_options[:disability_ids] = options[:disability_ids] if options[:disability_ids].present?
        cat[:questions] = Question.in_category(cat.id, new_options)

        # if this category has sub_categories, get them too
        if cat.has_children?
          new_options = {:child_of => cat.path_ids.join('/'), :category_type => options[:category_type]}
          new_options[:disability_id] = options[:disability_id] if options[:disability_id].present?
          new_options[:disability_ids] = options[:disability_ids] if options[:disability_ids].present?

          cat[:sub_categories] = with_questions(new_options)
        end
      
      end
    
    end

    return categories
  end

  # get all common question main categories and any special questions main categories if a question category id is provided  
  # possible options: question_category_id, disability_id(s), :venue_id, :is_certified
  def self.questions_categories_for_venue(options = {})
    categories = []
    options[:is_certified] = true if options[:is_certified].nil?

    # get custom questions
    if options[:question_category_id].present?
      options[:category_type] = options[:is_certified] == true ? TYPES['custom'] : TYPES['public_custom']
      categories << get_categories(options)      
    end

    
    # get common/public questions
    ops = {:category_type => options[:is_certified] == true ? TYPES['common'] : TYPES['public']}
    ops[:disability_id] = options[:disability_id] if options[:disability_id].present?
    ops[:disability_ids] = options[:disability_ids] if options[:disability_ids].present?
    ops[:venue_id] = options[:venue_id] if options[:venue_id].present?

    categories << get_categories(ops)      
    categories.flatten!    
    
    return categories
  end
  

  # get all common questions and any special questions if a question category id is provided  
  # possible options: question_category_id, disability_id(s), :venue_id, :is_certified
  def self.questions_for_venue(options = {})
    options[:is_certified] = true if options[:is_certified].nil?
    questions = []

    # get custom questions
    if options[:question_category_id].present?
      options[:category_type] = options[:is_certified] == true ? TYPES['custom'] : TYPES['public_custom']
      questions << with_questions(options)      
    end
    
    # get common/public questions
    ops = {:category_type => options[:is_certified] == true ? TYPES['common'] : TYPES['public']}
    ops[:disability_id] = options[:disability_id] if options[:disability_id].present?
    ops[:disability_ids] = options[:disability_ids] if options[:disability_ids].present?
    ops[:venue_id] = options[:venue_id] if options[:venue_id].present?

    questions << with_questions(ops)
    questions.flatten!    
    
    return questions
  end
  

  # get all questions for a venue that has custom questions
  # possible options: question_category_id, disability_id
  def self.custom_questions_for_venue(question_category_id, options = {})
    options[:is_certified] = true if options[:is_certified].nil?
    questions = []
    
    ops = {:category_type => options[:is_certified] == true ? TYPES['custom'] : TYPES['public_custom'], :question_category_id => question_category_id}
    ops[:disability_id] = options[:disability_id] if options[:disability_id].present?
    ops[:disability_ids] = options[:disability_ids] if options[:disability_ids].present?
    ops[:venue_id] = options[:venue_id] if options[:venue_id].present?

    questions << with_questions(ops)
    questions.flatten!

    return questions
  end


  # get all categories with no ancestor
  def self.all_main
    with_translations(I18n.locale).where(:ancestry => nil)
    .order('question_categories.sort_order, question_categories.category_type, question_category_translations.name')
  end
  

  #######################################
  ## calculate how many questions are in this array of question categories
  ## - have to look for sub categories in each category
  #######################################
  def self.number_questions(question_categories)
    num = 0
    if question_categories.present?
      question_categories.each do |qc|
        num += qc[:questions].length
      
        num += number_questions(qc[:sub_categories]) if qc[:sub_categories].present?
      end
    end
    return num
  end


  
  #######################################
  ## load all question categories, quetsions and pairings from the main spreadsheet
  #######################################
  def self.process_complete_csv_upload()
    path = "#{Rails.root}/db/spreadsheets/Accessibility Upload - Questions.csv"
    process_csv_upload(File.open(path, 'r'), true)
  end  
  
  #######################################
  ## load all question categories, quetsions and pairings from the main spreadsheet
  #######################################
  def self.update_csv_upload()
    path = "#{Rails.root}/db/spreadsheets/Accessibility Upload - Questions.csv"
    process_csv_upload(File.open(path, 'r'), false)
  end  
  
  #######################################
  ## load question categories, quetsions and pairings 
  ## from csv file
  ## - if delete_first is false then will update existing questions
  #######################################
  def self.process_csv_upload(file, delete_first=false)
		start = Time.now
    infile = file.read
    n, msg = 0, ""
    idx_category_id = 0
    idx_parent_name = 1
    idx_parent_name_ka = 2
    idx_parent_sort = 3
    idx_parent_type = 4
    idx_child_category_id = 5
    idx_child_name = 6
    idx_child_name_ka = 7
    idx_child_sort = 8
    idx_child_type = 9
    idx_type = 10
    idx_exists_id = 11
    idx_exists_parent_id = 12
    idx_question_id = 13
    idx_question = 14
    idx_question_ka = 15
    idx_question_sort = 16
    idx_validation_eq = 17
    idx_validation_eq_ka = 18
    idx_evidence_is_angle = 19
    idx_question_evidence1 = 20
    idx_question_evidence1_ka = 21
    idx_question_evidence2 = 22
    idx_question_evidence2_ka = 23
    idx_question_evidence3 = 24
    idx_question_evidence3_ka = 25
    idx_venue_name = 26
    idx_domestic_legal_req = 27
    idx_convention_category = 28
    idx_reference = 29
    idx_reference_ka = 30
    idx_help_text = 31
    idx_help_text_ka = 32
    current_parent, current_child, current_venue = nil

		original_locale = I18n.locale
    I18n.locale = :en

    disabilities = Disability.all
    convention_categories = ConventionCategory.with_translations(I18n.locale)

		QuestionCategory.transaction do
		  if delete_first
        puts "******** deleting all questions on record first"
        # quicker to do delete all instead of destroy        
        QuestionCategory.delete_all
        QuestionCategoryTranslation.delete_all
        Question.delete_all
        QuestionTranslation.delete_all
        QuestionPairing.delete_all
        QuestionPairingTranslation.delete_all
        QuestionPairingDisability.delete_all
        QuestionPairingDisabilityTranslation.delete_all
        PlaceEvaluation.delete_all
        PlaceEvaluationAnswer.delete_all
        PlaceEvaluationOrganization.delete_all
        PlaceImage.delete_all
        PlaceEvaluationImage.delete_all
        PlaceSummary.delete_all
        
		  end
		
		  CSV.parse(infile) do |row|
        question = nil
        startRow = Time.now
		    n += 1
        puts "@@@@@@@@@@@@@@@@@@ processing row #{n}"

        if n > 1
          # get question category
          # if the name does not match the last rows, create it if necessary
          if current_parent.nil? || current_parent[:name] != row[idx_parent_name].strip
            if row[idx_parent_name].blank?
	      		  msg = "Row #{n}: Parent Category Name is not provided"
			        raise ActiveRecord::Rollback
	      		  return msg
            end

          	puts "******** having to get parent: #{row[idx_parent_name]}"
            # need to create new question category or get it from db if already exists
            current_parent = get_category(row[idx_category_id], row[idx_parent_name], row[idx_parent_name_ka], row[idx_parent_sort], row[idx_parent_type])
          end

          if current_parent.blank? || current_parent[:id].blank?
	    		  msg = "Row #{n}: Could not find/create parent"
			      raise ActiveRecord::Rollback
	    		  return msg
          end

        	puts "******** - parent: #{current_parent[:id]}; #{current_parent[:name]}"
          
          # get child question category if present
          if row[idx_child_name].present?
          	puts "******** child exists!"
            if current_child.nil? || current_child[:name] != row[idx_child_name].strip
              if row[idx_parent_name].blank?
	        		  msg = "Row #{n}: Child Category Name is not provided"
			          raise ActiveRecord::Rollback
	        		  return msg
              end

            	puts "******** - having to get child: #{row[idx_child_name]}"
              # need to create new question category or get it from db if already exists
              current_child = get_category(row[idx_child_category_id], row[idx_child_name], row[idx_child_name_ka], row[idx_child_sort], row[idx_child_type], current_parent[:id])

              if current_child.blank? || current_child[:id].blank?
          		  msg = "Row #{n}: Could not find/create child"
		            raise ActiveRecord::Rollback
          		  return msg
              end
            end
          	puts "******** - child: #{current_child[:id]}; #{current_child[:name]}"
          else
            current_child = nil
          end

          # see if question already on file
          if row[idx_question].blank?
      		  msg = "Row #{n}: Question is not provided"
	          raise ActiveRecord::Rollback
      		  return msg
          end 
          
        	puts "******** geting question: #{row[idx_question]}"
          question = get_question(row[idx_question_id], row[idx_question], row[idx_question_ka])

          if question.blank? || question[:id].blank?
      		  msg = "Row #{n}: Could not find/create question"
	          raise ActiveRecord::Rollback
      		  return msg
          end
          
          # build evidence
        	puts "******** building evidence"
          qc_id = current_child.blank? ? current_parent[:id] : current_child[:id]
          # validation equation
          val_eq = row[idx_validation_eq].present? ? row[idx_validation_eq].strip : nil
          val_eq_ka = row[idx_validation_eq_ka].present? ? row[idx_validation_eq_ka].strip : val_eq
          # strip out all # . < > ( ) to be left with just the units
          val_eq_units = nil
          val_eq_wout_units = nil
          val_eq_units = val_eq.gsub(/[0-9.<>()]/, '').split(' and ')[0].strip if val_eq.present?
          val_eq_wout_units = val_eq.gsub(val_eq_units, '').strip if val_eq_units.present?
          val_eq_units_ka = nil
          val_eq_wout_units_ka = nil
          val_eq_units_ka = val_eq_ka.gsub(/[0-9.<>()]/, '').gsub(' and ', ' და ').split(' და ')[0].strip if val_eq_ka.present?
          val_eq_wout_units_ka = val_eq_ka.gsub(val_eq_units_ka, '').strip if val_eq_units_ka.present?
          # evidence fields
          is_evidence_angle = row[idx_evidence_is_angle].present? ? row[idx_evidence_is_angle].to_s.strip.to_bool : false
          ev1 = row[idx_question_evidence1].present? ? row[idx_question_evidence1] : nil
          ev2 = row[idx_question_evidence2].present? ? row[idx_question_evidence2] : nil
          ev3 = row[idx_question_evidence3].present? ? row[idx_question_evidence3] : nil
          ev1_ka = row[idx_question_evidence1_ka].present? ? row[idx_question_evidence1_ka] : ev1
          ev2_ka = row[idx_question_evidence2_ka].present? ? row[idx_question_evidence2_ka] : ev2
          ev3_ka = row[idx_question_evidence3_ka].present? ? row[idx_question_evidence3_ka] : ev3
          # get units inside ()
          ev1_units = nil
          ev2_units = nil
          ev3_units = nil
          if ev1.present?
            ev1_units = ev1.match(/\((.*)\)/) 
            if ev1_units.nil? && is_evidence_angle == true
        		  msg = "Row #{n}: Units for Evidence 1 are missing. Please put something in between () like 'Number (#)'"
              raise ActiveRecord::Rollback
        		  return msg
            end    		  
            ev1_units = ev1_units.present? ? ev1_units[1].strip : nil
          end
          if ev2.present?
            ev2_units = ev2.match(/\((.*)\)/) 
            if ev2_units.nil? && is_evidence_angle == true
        		  msg = "Row #{n}: Units for Evidence 2 are missing. Please put something in between () like 'Number (#)'"
              raise ActiveRecord::Rollback
        		  return msg
            end    		  
            ev2_units = ev2_units.present? ? ev2_units[1].strip : nil
          end
          if ev3.present?
            ev3_units = ev3.match(/\((.*)\)/) 
            if ev3_units.nil? && is_evidence_angle == true
        		  msg = "Row #{n}: Units for Evidence 3 are missing. Please put something in between () like 'Number (#)'"
              raise ActiveRecord::Rollback
        		  return msg
            end    		  
            ev3_units = ev3_units.present? ? ev3_units[1].strip : nil
          end

          ev1_units_ka = nil
          ev2_units_ka = nil
          ev3_units_ka = nil
          if ev1_ka.present?
            ev1_units_ka = ev1_ka.match(/\((.*)\)/) 
            if ev1_units_ka.nil? && is_evidence_angle == true
              msg = "Row #{n}: Units for Georgian Evidence 1 are missing. Please put something in between () like 'Number (#)'"
              raise ActiveRecord::Rollback
              return msg
            end         
            ev1_units_ka = ev1_units_ka.present? ? ev1_units_ka[1].strip : ev1_units
          end
          if ev2_ka.present?
            ev2_units_ka = ev2_ka.match(/\((.*)\)/) 
            if ev2_units_ka.nil? && is_evidence_angle == true
              msg = "Row #{n}: Units for Georgian Evidence 2 are missing. Please put something in between () like 'Number (#)'"
              raise ActiveRecord::Rollback
              return msg
            end         
            ev2_units_ka = ev2_units_ka.present? ? ev2_units_ka[1].strip : ev2_units
          end
          if ev3_ka.present?
            ev3_units_ka = ev3_ka.match(/\((.*)\)/) 
            if ev3_units_ka.nil? && is_evidence_angle == true
              msg = "Row #{n}: Units for Georgian Evidence 3 are missing. Please put something in between () like 'Number (#)'"
              raise ActiveRecord::Rollback
              return msg
            end         
            ev3_units_ka = ev3_units_ka.present? ? ev3_units_ka[1].strip : ev3_units
          end

          # validation equation validation
          # - if present, at least evidence1 must have content
          # - units in evidence1 and eq must match unless is evidence angle
          # - if is evidence angle, then evidence 1-3 must be present
          if val_eq.present? 
            # evidence 1 exists?
            if ev1.blank? || ev1_ka.blank?
        		  msg = "Row #{n}: A Validation Equation exists but there is no Evidence 1 text"
	            raise ActiveRecord::Rollback
        		  return msg
      		  
            # evidence angle and all 3 evidence
            elsif is_evidence_angle == true && (!(ev1.present? && ev2.present? && ev3.present?) || !(ev1_ka.present? && ev2_ka.present? && ev3_ka.present?))
        		  msg = "Row #{n}: This question is marked as an Evidence is Angle question, but Evidence 1, 2, or 3 text is missing. All three are required and should be in format of 1: Height; 2: Depth; 3: Angle"
	            raise ActiveRecord::Rollback
        		  return msg
            
      		  # matching units
            elsif is_evidence_angle == false && (!(val_eq_units.downcase == ev1_units.downcase) || !(val_eq_units_ka.downcase == ev1_units_ka.downcase))
        		  msg = "Row #{n}: The units of Evidence 1 do match the units in the Validation Equation"
	            raise ActiveRecord::Rollback
        		  return msg
              
            end          
          end
          
          # see if qp already exists
          qp = QuestionPairing.includes(:question_pairing_translations).find_by_unique_id(row[idx_question_id])
          
          if qp.present?
            puts "******** question pairing exists, updating if needed"
            qp.question_category_id = qc_id
            qp.question_id = question[:id]
            qp.sort_order = row[idx_question_sort]
            qp.exists_id = row[idx_exists_id].present? ? row[idx_exists_id].strip : nil 
            qp.exists_parent_id = row[idx_exists_parent_id].present? ? row[idx_exists_parent_id].strip : nil
            qp.is_domestic_legal_requirement = row[idx_domestic_legal_req].present? ? row[idx_domestic_legal_req].to_s.strip.to_bool : false
            qp.is_evidence_angle = is_evidence_angle 

            qp.question_pairing_translations.each do |trans|
              if trans.locale == 'ka'
                  trans.evidence1 = ev1_ka
                  trans.evidence1_units = ev1_units_ka
                  trans.evidence2 = ev2_ka
                  trans.evidence2_units = ev2_units_ka
                  trans.evidence3 = ev3_ka
                  trans.evidence3_units = ev2_units_ka
                  trans.validation_equation = val_eq_ka 
                  trans.validation_equation_units = val_eq_units_ka
                  trans.validation_equation_wout_units = val_eq_wout_units_ka
                  trans.reference = row[idx_reference_ka].present? ? row[idx_reference_ka].strip : row[idx_reference].present? ? row[idx_reference].strip : nil
              elsif trans.locale = 'en'
                  trans.evidence1 = ev1
                  trans.evidence1_units = ev1_units
                  trans.evidence2 = ev2
                  trans.evidence2_units = ev2_units
                  trans.evidence3 = ev3
                  trans.evidence3_units = ev2_units
                  trans.validation_equation = val_eq 
                  trans.validation_equation_units = val_eq_units 
                  trans.validation_equation_wout_units = val_eq_wout_units 
                  trans.reference = row[idx_reference].present? ? row[idx_reference].strip : nil
              end
            end

            if !qp.save
              msg = "Row #{n}: Could not update question pairing record due to this error: #{qp.errors.full_messages.join(', ')}"
              raise ActiveRecord::Rollback
              return msg
            end

          else
            puts "******** creating question pairing"
            qp = QuestionPairing.new(
              :question_category_id => qc_id, 
              :question_id => question[:id], 
              :sort_order => row[idx_question_sort], 
              :exists_id => row[idx_exists_id].present? ? row[idx_exists_id].strip : nil,
              :exists_parent_id => row[idx_exists_parent_id].present? ? row[idx_exists_parent_id].strip : nil,
              :is_domestic_legal_requirement => row[idx_domestic_legal_req].present? ? row[idx_domestic_legal_req].to_s.strip.to_bool : false,
              :validation_equation => val_eq, 
              :validation_equation_units => val_eq_units, 
              :validation_equation_wout_units => val_eq_wout_units, 
              :is_evidence_angle => is_evidence_angle,
              :unique_id => row[idx_question_id]
            )
                
            # add translations
            I18n.available_locales.each do |locale|
              # evidence 1-3 gathered above
              ref = row[idx_reference].present? ? row[idx_reference].strip : nil
              help = row[idx_help_text].present? ? row[idx_help_text].strip : nil
              ref_ka = row[idx_reference_ka].present? ? row[idx_reference_ka].strip : nil
              help_ka = row[idx_help_text_ka].present? ? row[idx_help_text_ka].strip : nil
              
              # if the locale is georgian and georgian text exists, use it
              ev1 = ev1_ka if locale == :ka && ev1_ka.present?
              ev2 = ev2_ka if locale == :ka && ev2_ka.present?
              ev3 = ev3_ka if locale == :ka && ev3_ka.present?
              val_eq = val_eq_ka if locale == :ka && val_eq_ka.present?
              val_eq_units = val_eq_units_ka if locale == :ka && val_eq_units_ka.present?
              val_eq_wout_units = val_eq_wout_units_ka if locale == :ka && val_eq_wout_units_ka.present?
              ref = ref_ka if locale == :ka && ref_ka.present?
              help = help_ka if locale == :ka && help_ka.present?
              
              qp.question_pairing_translations.build(:locale => locale, 
                  :evidence1 => ev1, :evidence1_units => ev1_units,
                  :evidence2 => ev2, :evidence2_units => ev2_units,
                  :evidence3 => ev3, :evidence3_units => ev2_units,
                  :validation_equation => val_eq, 
                  :validation_equation_units => val_eq_units, 
                  :validation_equation_wout_units => val_eq_wout_units, 
                  :reference => ref, :help_text => help)
            end

            if !qp.save
              msg = "Row #{n}: Could not create question pairing record due to this error: #{qp.errors.full_messages.join(', ')}"
              raise ActiveRecord::Rollback
              return msg
            end
            
          end

          # add convention catgories
          # there might be multiple categories for a question
          # - so split by ; and AND
          conv_cat = row[idx_convention_category].present? ? row[idx_convention_category].strip : nil
          if conv_cat.present?
            conv_cats = []
            conv_ids = []
            if conv_cat.index('AND').present?
              conv_cats = conv_cat.split('AND')
            elsif conv_cat.index(';').present?
              conv_cats = conv_cat.split(';')
            else
              # no ; or and, so assume just one convention
              conv_cats << conv_cat
            end
            conv_cats.map!{|x| x.strip}
            
            # for each convention category, look for the matching record in db and save id if found
            conv_cats.each do |cat|
              if cat.present?
                index = convention_categories.index{|x| x.name.downcase == cat.downcase.strip}
                conv_cat_id = index.present? ? convention_categories[index].id : nil
                
                if conv_cat_id.present?
                  conv_ids << conv_cat_id                
                else
            		  msg = "Row #{n}: Could not match convention category '#{cat}' with what is in the database. Please make sure it is spelled correctly."
	                raise ActiveRecord::Rollback
            		  return msg
                end
              end
            end

            # save the ids
            conv_ids.each do |conv_id|
              qp.question_pairing_convention_categories.create(:convention_category_id => conv_id) if qp.question_pairing_convention_categories.index{|x| x.convention_category_id == conv_id}.nil?
            end
          end          
          
         
          # add disability types if needed
          types = row[idx_type].present? ? row[idx_type].split(',') : nil
          puts "******** question pairing needs disability types: '#{types}'"
        	puts "******** question pairing already has disability types: '#{qp.disabilities.map{|x| x.code}}'"
          if types.blank?
      		  msg = "Row #{n}: Could not find disability type"
	          raise ActiveRecord::Rollback
      		  return msg
          else
            # get records for these types
            disability_records = disabilities.select{|x| types.index(x.code).present?}

            if disability_records.present?
              # remove existing types if not needed anymore
              qp.question_pairing_disabilities.each do |record|
                puts "******** - checking if existing question pairing of disability id: #{record.disability_id} is still needed"
                if disability_records.index{|x| x.id == record.disability_id}.nil?
                  puts "******** --> disability type is no longer needed, deleting"
                  record.destroy
                end
              end

              # add or update types
              disability_records.each do |dis|
              	puts "******** - checking question pairing for disability type: #{dis.code}"
                # see if already exists
                dis_index = qp.question_pairing_disabilities.index{|x| x.disability_id == dis.id}
                if dis_index.nil?
                  puts "******** -> does not have disability type, adding"
                  # not exist yet, so add it
                  qpd = qp.question_pairing_disabilities.build(:disability_id => dis.id)
                  # add translations
                  I18n.available_locales.each do |locale|
                    help = row[idx_help_text].present? ? row[idx_help_text].strip : nil
                    help_ka = row[idx_help_text_ka].present? ? row[idx_help_text_ka].strip : nil
                    
                    # if the locale is georgian and georgian text exists, use it
                    help = help_ka if locale == :ka && help_ka.present?

                    # create translations even if help text is not present
                    qpd.question_pairing_disability_translations.build(:locale => locale, :content => help) 

                    if !qpd.save
                      msg = "Row #{n}: Could not create question pairing disability record due to this error: #{qpd.errors.full_messages.join(', ')}"
                      raise ActiveRecord::Rollback
                      return msg
                    end
                  end

                else
                  puts "******** -> already has disability type, so update content"

                  # alread exists, so update content
                  qpd = qp.question_pairing_disabilities[dis_index]
                  puts "******** -> existing record = #{qpd.inspect}"

                  # check translations
                  I18n.available_locales.each do |locale|
                    help = row[idx_help_text].present? ? row[idx_help_text].strip : nil
                    help_ka = row[idx_help_text_ka].present? ? row[idx_help_text_ka].strip : nil
                    
                    # if the locale is georgian and georgian text exists, use it
                    help = help_ka if locale == :ka && help_ka.present?

                    # if text present, update record
                    # else, reset record if it already exists
                    trans = qpd.question_pairing_disability_translations.select{|x| x.locale == locale.to_s}.first
                    if help.present? && trans.present?
                      puts "******** --> updating existing help content"
                      # update existing
                      trans.content = help
                    elsif help.present? 
                      puts "******** --> creating help content"
                      # add record
                      qpd.question_pairing_disability_translations.build(:locale => locale, :content => help) 
                    elsif trans.present?
                      puts "******** --> help text no longer exists, reseting to nil"
                      trans.content = nil
                    end

                    if !qpd.save
                      msg = "Row #{n}: Could not update question pairing disability record due to this error: #{qpd.errors.full_messages.join(', ')}"
                      raise ActiveRecord::Rollback
                      return msg
                    end
                  end

                end
                if dis_index.present? && qp.disabilities.index{|x| disabilities[dis_index].id == x.id}.nil?
                	puts "******** --> adding"
                  qp.disabilities << disabilities[dis_index]
                end
              end
            end
          end
          
         
          # if venue provided, add question category id to venue
          if row[idx_venue_name].present? && ((current_venue.blank? && row[idx_venue_name].present?) || (current_venue.present? && current_venue[:name] != row[idx_venue_name].strip))
          	puts "******** having to get venue: #{row[idx_venue_name]}"
            current_venue = get_venue(row[idx_venue_name])

            if current_venue.blank?
        		  msg = "Row #{n}: Could not find venue - make sure the venue already exists in the system"
		          raise ActiveRecord::Rollback
        		  return msg
            end
          elsif row[idx_venue_name].blank?
            current_venue = nil
          end
          
          if current_venue.present?
          	puts "******** adding question category id to venue: #{row[idx_venue_name]}; #{current_venue.inspect}"
            current_venue.custom_question_category_id = current_parent[:id] if current_parent[:category_type] == TYPES['custom']
            current_venue.custom_public_question_category_id = current_parent[:id] if current_parent[:category_type] == TYPES['public_custom']
            current_venue.save
          end
         
          
        	puts "******** time to process row: #{Time.now-startRow} seconds"
          puts "************************ total time so far : #{Time.now-start} seconds"
        end
      end  
  
		end

		# reset the locale
		I18n.locale = original_locale

    # load the venue question category matrix
    VenueQuestionCategory.process_complete_csv_upload if msg.blank?

  	puts "****************** time to build question categories from csv: #{Time.now-start} seconds for #{n} rows"

    return msg
  end
  
  
  ######################################
  ######################################
  ######################################
private
  # get question category and if not exist, create it
  def self.get_category(unique_id, name, name_ka, sort, category_type, parent_id=nil)
    qc = nil
    unique_id.strip! if unique_id.present?
    name.strip! if name.present?
    name_ka.strip! if name_ka.present?
    sort.strip! if sort.present?
    category_type.strip! if category_type.present?

    x = includes(:question_category_translations).find_by_unique_id(unique_id)

#    x = select('question_categories.id').includes(:question_category_translations)
#          .where(:question_categories => {:sort_order => sort, :category_type => TYPES[category_type], :ancestry => nil}, 
#                  :question_category_translations => {:locale => I18n.locale, :name => name})
          
    if x.present?
      puts "////////// category exists, updating if needed"
      # update the record if needed
      x.sort_order = sort if x.sort_order != sort
      x.category_type = TYPES[category_type] if x.category_type != TYPES[category_type]
      x.parent_id = parent_id if x.parent_id != parent_id

      # update translations if needed
      x.question_category_translations.each do |trans|
        if trans.locale == 'ka' && trans.name != name_ka
          trans.name = name_ka.present? ? name_ka : name
        elsif trans.locale == 'en' && trans.name != name
          trans.name = name 
        end
      end

      x.save

      # save question category into variable
      trans = x.question_category_translations.select{|y| y.locale == I18n.locale.to_s}.first
      qc = {:id => x.id, :name => trans.name, :category_type => x.category_type}
    end

    if qc.nil?
      puts "////////// creating category"
      qc = QuestionCategory.create(:category_type => TYPES[category_type], :sort_order => sort, :unique_id => unique_id)
      I18n.available_locales.each do |locale|
        x = name
        x = name_ka if locale == :ka && name_ka.present?
        qc.question_category_translations.create(:locale => locale, :name => x)
      end
      if parent_id.present?
        qc.parent_id = parent_id
        qc.save
      end
      qc[:name] = name
    end
    
    return qc
  end

  # get question and if not exist, create it
  def self.get_question(unique_id, name, name_ka)
    q = nil
    unique_id.strip! if unique_id.present?
    name.strip! if name.present?
    name_ka.strip! if name_ka.present?

    x = Question.includes(:question_translations).find_by_unique_id(unique_id)

    if x.present?
      puts "////////// question exists, updating if needed"
      # update translations if needed
      x.question_translations.each do |trans|
        if trans.locale == 'ka' && trans.name != name_ka
          trans.name = name_ka.present? ? name_ka : name
        elsif trans.locale == 'en' && trans.name != name
          trans.name = name 
        end
      end

      x.save

      # save question into variable
      trans = x.question_translations.select{|y| y.locale == I18n.locale.to_s}.first
      q = {:id => x.id, :name => trans.name}
    end

    if q.nil?
      puts "////////// creating question"
      q = Question.create(:unique_id => unique_id)
      I18n.available_locales.each do |locale|
        x = name
        x = name_ka if locale == :ka && name_ka.present?
        q.question_translations.create(:locale => locale, :name => x)
      end
    end
    
    return q
  end

  # get venue category
  def self.get_venue(name)
    v = nil
    name.strip! if name.present?

    x = Venue.includes(:venue_translations)
          .where(:venue_translations => {:locale => I18n.locale, :name => name})
          
    if x.present?
      v = x.first 
      v[:name] = name
    end
    
    return v
  end


  def self.get_categories(options={})
    categories = nil

    categories = with_translations(I18n.locale).order('question_categories.sort_order asc')
    # if want children questions to get children
    # otherwise only get parents
    if options[:child_of].present?
      categories = categories.where('question_categories.ancestry = ?', options[:child_of]) 
    else
      categories = categories.where('question_categories.ancestry is null') 
    end
    # filter by category type
    categories = categories.where('question_categories.category_type = ?', options[:category_type]) if options[:category_type].present?
    # filter by question category (venue with custom questions)
    categories = categories.where('question_categories.id = ?', options[:question_category_id]) if options[:question_category_id].present?
    # only get categories that this venue is assigned to
    categories = categories.joins(:venue_question_categories).where('venue_question_categories.venue_id = ?', options[:venue_id]) if options[:venue_id].present? && options[:category_type] == TYPES['common']

    return categories
  end
end
