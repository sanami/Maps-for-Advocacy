class PlaceEvaluation < ActiveRecord::Base

  belongs_to :place
  belongs_to :user
  belongs_to :disability
  has_many :place_evaluation_answers, :dependent => :destroy
  accepts_nested_attributes_for :place_evaluation_answers
  attr_accessible :place_id, :user_id, :place_evaluation_answers_attributes, :created_at, :disability_id, :is_certified
  validates :user_id, :disability_id, :presence => true

  after_create :update_summaries

  ANSWERS = {'no_answer' => 0, 'not_relevant' => 1, 'needs' => 2, 'has_bad' => 3, 'has_good' => 4, 'has' => 5}

  # update the summary for this place
  def update_summaries
    if self.is_certified?
      PlaceSummary.update_certified_summaries(self.place_id, self.id)
    else
      PlaceSummary.update_summaries(self.place_id, self.id)
    end
  end
  
  def self.answer_key_name(value)
    ANSWERS.keys[ANSWERS.values.index(value)]
  end
  
  def self.with_answers(place_id, options={})
    options[:is_certified] = false if options[:is_certified].nil?

    includes(:place_evaluation_answers)
    .where(:place_id => place_id, :is_certified => options[:is_certified])  
    .where(:disability_id => options[:disability_id]) if options[:disability_id].present?
  end
  
  def self.sorted
    order('place_evaluations.created_at desc, place_evaluations.user_id asc')
  end

  # get all evaluations for the provided places
  # - place_ids: array of place ids
  def self.in_places(place_ids)
    if place_ids.present?
      where(place_id: place_ids)
    end
  end
  
  # get number of users that have submitted evaluations
  def self.user_count
    select('distinct user_id').count
  end
  
  # get all of the answers for a place
  # so that a summary can be computed
  # place_id: id of place to get answers for
  # options:
  # - is_certified: get answers that are certified (default = false)
  # - place_evaluation_id: get answers for a specific evaluation
  def self.with_answers_for_summary(place_id, options={})
    options[:is_certified] = false if options[:is_certified].nil?
    
    x = select('place_evaluations.id, place_evaluations.disability_id, place_evaluation_answers.question_pairing_id, place_evaluation_answers.answer')
    .joins(:place_evaluation_answers)
    .where(:place_id => place_id, :is_certified => options[:is_certified])  
    
    x = x.where('place_evaluations.id = ?', options[:place_evaluationd_id]) if options[:place_evaluationd_id].present?
    
    return x
  end


  # get all of the answers for a venue
  # so that a summary can be computed
  # venue_id: id of venue to get answers for
  # options:
  # - is_certified: get answers that are certified (default = false)
  def self.with_answers_for_venue_summary(venue_id, options={})
    options[:is_certified] = false if options[:is_certified].nil?
    
    x = select('place_evaluations.id, place_evaluations.place_id, place_evaluations.disability_id, place_evaluation_answers.question_pairing_id, place_evaluation_answers.answer')
    .joins(:place_evaluation_answers, :place)
    .where(['places.venue_id = ? and place_evaluations.is_certified = ?', venue_id, options[:is_certified]])  
    
    return x
  end


  # get all of the answers for a venue category
  # so that a summary can be computed
  # venue_category_id: id of venue category to get answers for
  # options:
  # - is_certified: get answers that are certified (default = false)
  def self.with_answers_for_venue_category_summary(venue_category_id, options={})
    options[:is_certified] = false if options[:is_certified].nil?
    
    x = select('place_evaluations.id, place_evaluations.place_id, place_evaluations.disability_id, place_evaluation_answers.question_pairing_id, place_evaluation_answers.answer')
    .joins(:place_evaluation_answers, :place => :venue)
    .where(['venues.venue_category_id = ? and place_evaluations.is_certified = ?', venue_category_id, options[:is_certified]])  
    
    return x
  end



end
