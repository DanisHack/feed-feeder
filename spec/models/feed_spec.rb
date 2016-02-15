require 'rails_helper'

RSpec.describe Feed, type: :model do
  describe "#process_feed_contents" do
    before(:each) do
      Feed.destroy_all
      # Get the feeds contents and create the model
      @feed_content = feed_content(:random)
      @feed = FactoryGirl.create :feed
      @feed.update(url: @feed_content.url) if @feed_content.url.present?
    end

    it 'inserts the correct fields' do
      stub_request(:any, @feed.url).to_return body: @feed_content.content
      stub_feed_run_python_method
      @feed.process_feed_contents
      @feed.feed_source.items.each do |item|
        expect(item.feed_id).to eq(@feed.id)
        expect(item.body).to_not eq(nil)
      end
    end

    it 'handles duplicates' do
      # Use feed content with duplicates
      stub_request(:any, @feed.url).to_return body: feed_content(:with_duplicates).content
      stub_feed_run_python_method
      @feed.process_feed_contents
      @feed.process_feed_contents
      expect(@feed.feed_source.items.count).to eq(1)
    end

    it 'prepends the feed domain if the URL starts with /' do
      # Use feed content that doesn't have relative URLs
      stub_request(:any, @feed.url).to_return body: feed_content(:with_relative_urls).content
      stub_feed_run_python_method
      @feed.process_feed_contents
      @feed.feed_source.items.each do |item|
        expect(item.url).to_not start_with('/')
      end
    end
  end

  Dir.glob(Rails.root.join('spec/fixtures/feeds/*.xml')).sort.each do |feed_path|
    feed_filename = File.basename(feed_path, '.xml')
    describe "#process_feed_contents with feed #{feed_filename}.xml" do
      before(:each) do
        Feed.destroy_all
        # Get the feeds contents and create the model
        @feed_content = feed_content(feed_filename)
        @feed = FactoryGirl.create :feed
        @feed.update(url: @feed_content.url) if @feed_content.url.present?
      end

      it 'adds feed items' do
        stub_request(:any, @feed.url).to_return body: @feed_content.content
        stub_feed_run_python_method
        @feed.process_feed_contents
        expect(@feed.feed_source.items.count).to_not eq(0)
      end
    end
  end

end
