require 'sinatra'
require 'selenium-webdriver'
require 'csv'
require 'tempfile'
require 'open-uri'

get '/' do
  erb :index
end

post '/submit' do
  indeed_url = params[:indeed_url]
  limit = params[:limit]

  redirect to("/scrapping?indeed_url=#{indeed_url}&limit=#{limit}")
end

get '/scrapping' do
  @indeed_url = params[:indeed_url]
  @limit = params[:limit]

  erb :scrapping
end

get '/done' do
  erb :done
end

get '/scrape_indeed' do
  # Ensure that the INDEED_URL parameter is provided
  raise 'Please Provide URLs' if params[:indeed_url].nil? || params[:indeed_url].empty?

  # Set up Selenium WebDriver
  driver = Selenium::WebDriver.for(:chrome)
  driver.get(params[:indeed_url])

  # Set the scraping limit (default is 10)
  limit = params.fetch('limit', 10).to_i
  page_count = 0

  temp_file = Tempfile.new(parameterize(params[:indeed_url]))

  begin
    CSV.open(temp_file, 'w', headers: true) do |csv|
      csv << ['Job Title', 'URL']

      loop do
        remove_blocker(driver)

        job_titles = driver.find_elements(:css, '.jcs-JobTitle')
        titles = job_titles.map(&:text)
        urls = job_titles.map { |title| title.attribute('href') }

        data = titles.zip(urls)

        data.each { |row| csv << row }

        page_count += 1
        break if page_count >= limit

        next_button = wait_for_element(driver, :css, 'a[data-testid="pagination-page-next"]')
        break unless next_button

        next_page_url = next_button.attribute('href')
        driver.navigate.to(next_page_url)
      rescue Selenium::WebDriver::Error
        break
      end
    end

    temp_file.rewind

    # Set content type and disposition for the response
    content_type 'application/csv'
    attachment "#{parameterize(params[:indeed_url])}.csv"

    # Download the file content over HTTP
    temp_file.read
    redirect to('/done')
  ensure
    temp_file.close! if temp_file
    driver.quit if driver
  end
end

def wait_for_element(driver, locator_type, locator)
  wait = Selenium::WebDriver::Wait.new(timeout: 10)

  begin
    wait.until { driver.find_element(locator_type, locator) }
  rescue Selenium::WebDriver::Error::TimeoutError
    return nil
  end
end

def remove_blocker(driver)
  begin
    popup_element = driver.find_element(:id, 'mosaic-desktopserpjapopup')
    first_button = popup_element.find_element(:tag_name, 'button')
    first_button.click
  rescue Selenium::WebDriver::Error::NoSuchElementError
    # Ignore the exception if the element is not found
  end
end

def parameterize(string)
  string.downcase.gsub(/[^a-z0-9]+/, '-').chomp('-')
end
