require 'active_support/concern'

module HasUserSearch
  extend ActiveSupport::Concern

  included do
    def self.search(params, timezone, current_full_address)
      join_tables
        .who_can_help_with(params[:program])
        .is_available(params, timezone)
        .based_on_distance(params, current_full_address)
        .paginate_results(params[:page])
        .by_order(params, current_full_address)
    end

    scope :join_tables, proc {
      includes(:programs, :availabilities)
    }

    scope :who_can_help_with, proc { |program|
      if program.present?
        volunteers.active.with_availabilities.where({
            :programs => { id: program.split(/,/) }
        })
      else
        message = I18n.t('custom_errors.messages.missing_program')
        raise Contexts::Availabilities::Errors::ProgramMissing, message
      end
    }

    scope :paginate_results, proc { |page|
      if page.present?
        paginate(:page => page, :per_page => 6)
      else
        paginate(:page => 1, :per_page => 6)
      end
    }

    scope :based_on_distance, proc { |params, current_full_address|
      if params[:distance].present? && current_full_address.present?
        near(current_full_address, params[:distance], :order => false)
      end
    }

    scope :by_order, proc { |params, current_full_address|
      if params[:order].present?
        case params[:order]
        when "highest"
          order(average_rating: :desc)
        when "newest"
          order(created_at: :desc)
        when "closest"
          near(current_full_address, 10000, :order => "")
        when 'last'
          order(last_sign_in_at: :desc)
        else
          message = I18n.t('custom_errors.messages.incorrect_order')
          raise Contexts::Availabilities::Errors::IncorrectOrder, message
        end
      else
        order(last_sign_in_at: :desc)
      end
    }

    scope :is_available, proc { | params, timezone |
      if params[:day].present?
        I18n.locale = :en
        days = params[:day].split(/,/)

        queries = []
        days.each { |day|
          day_index = day.to_i
          day_month = "#{I18n.t('date.day_names')[day_index]}, #{day_index + 1} Jan 2001"

          Time.zone = timezone
          start_of_day = Time.zone.parse("#{day_month} 00:00")&.utc
          end_of_day = Time.zone.parse("#{day_month} 23:59")&.utc
          infinity = DateTime::Infinity.new

          start_query = if params[:start_time]
                          Time.zone.parse("#{day_month} #{params[:start_time]}")&.utc
                        else
                          start_of_day
                        end

          end_query = if params[:end_time]
                        Time.zone.parse("#{day_month} #{params[:end_time]}")&.utc
                      else
                        end_of_day
                      end


          Time.zone = 'UTC'

          # check end_query > end of day then add a statement
          if end_query.strftime("%d").to_i != (day_index + 1)
            first_statement = where({ :availabilities => {
                :start_time => start_query..end_of_day,
                :end_time => start_query..end_of_day
            }})

            queries << first_statement

            second_statement = where({ :availabilities => {
                :start_time => infinity..end_query,
                :end_time => infinity..end_query
            }})

            queries << second_statement

            # check start_query < start of day then add a statement
          elsif start_query.strftime("%d").to_i != (day_index + 1)
            first_statement = where({ :availabilities => {
                :start_time => start_query..infinity,
                :end_time => start_query..infinity
            }})

            queries << first_statement

            second_statement = where({ :availabilities => {
                :start_time => start_of_day..end_query,
                :end_time => start_of_day..end_query
            }})

            queries << second_statement

          else

            statement = where({ :availabilities => {
                :start_time => start_query..end_query,
                :end_time => start_query..end_query
            }})

            queries << statement
          end
        }

        queries.inject(:or)
      else
        message = I18n.t('custom_errors.messages.missing_day')
        raise Contexts::Availabilities::Errors::DayMissing, message
      end
    }
  end

  module ClassMethods

  end
end
