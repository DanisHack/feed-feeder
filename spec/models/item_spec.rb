require 'rails_helper'

RSpec.describe Item, type: :model do
  describe '#self.send_missing_to_api' do
    it 'sends the missing items to the API' do
      # Initialise fake lateral (see ../support/fake_lateral.rb)
      init_fake_lateral!

      # This creates two feed sources, the first with 1 item, the other with 251 items
      FactoryGirl.create :item
      FactoryGirl.create_list :item, 251, feed_source: FactoryGirl.create(:feed_source, :with_feeds)

      # Call the method and check that it sent 1 + 250 requests to Lateral API
      Item.send_missing_to_api
      expect(WebMock).to have_requested(:post, %r{api.lateral.io/documents/\d+$}).times(251)

      # Reset webmock counting
      WebMock.reset! && init_fake_lateral!

      # Call the method again and check the remaining item was sent
      Item.send_missing_to_api
      expect(WebMock).to have_requested(:post, %r{api.lateral.io/documents/\d+$}).times(1)
    end

    it "doesn't send items published over a week old" do
      # Initialise fake lateral (see ../support/fake_lateral.rb)
      init_fake_lateral!

      # Create a 1 day old item and 5 2 week old items
      FactoryGirl.create :item, published: 1.day.ago
      FactoryGirl.create_list :item, 5, published: 2.weeks.ago

      # Call the method and check that it sent 1 request to Lateral API
      Item.send_missing_to_api
      expect(WebMock).to have_requested(:post, %r{api.lateral.io/documents/\d+$}).times(1)
    end

    it "doesn't send items that were already sent to the api" do
      # Initialise fake lateral (see ../support/fake_lateral.rb)
      init_fake_lateral!

      # Create an item that was sent to the api and 5 that weren't
      FactoryGirl.create :item, sent_to_api: true
      FactoryGirl.create_list :item, 5, sent_to_api: false

      # Call the method and check that it sent 5 requests to Lateral API
      Item.send_missing_to_api
      expect(WebMock).to have_requested(:post, %r{api.lateral.io/documents/\d+$}).times(5)
    end
  end

  describe '#send_to_api' do
    before(:each) do
      init_fake_lateral!
      @key = FactoryGirl.create :key
      @item = FactoryGirl.create :item
    end

    it 'adds an item' do
      stub_request(:any, %r{api.lateral.io/documents/.*}).to_return body: { id: @item.id }.to_json
      @item.send_to_api(@key)
      @item.reload
      expect(@item.sent_to_api).to eq(true)
      expect(@item.lateral_id).to_not eq(nil)
      meta = { feed_source_id: @item.feed_source.id, title: @item.title, url: @item.url, image: @item.image,
               summary: @item.summary, guid: @item.guid }
      expected_request = { body: hash_including(text: @item.body, meta: meta) }
      url = %r{api.lateral.io/documents/#{@item.id}$}
      expect(WebMock).to have_requested(:post, url).with(expected_request)
    end

    it "doesn't add if is duplicate in API" do
      stub_request(:any, %r{api.lateral.io/documents/similar}).to_return body: '[{ "similarity": 1 }]'
      @item.send_to_api(@key)
      @item.reload
      expect(@item.sent_to_api).to eq(true)
      expect(@item.error).to eq("{\"message\":\"Duplicate\"}")
    end

    it "doesn't add if the body is invalid" do
      @item.update_attributes(body: '')
      @item.send_to_api(@key)
      @item.reload
      expect(@item.sent_to_api).to eq(true)
      expect(@item.error).to eq("{\"message\":\"Invalid body\"}")
    end

    it 'creates tags in the api from authors' do
      item = FactoryGirl.create :item, :with_authors
      stub_request(:any, %r{api.lateral.io/documents/#{item.id}/tags/.*$}).to_return body: ''
      item.send_to_api(@key)
      item.authors.each do |author|
        expected_request = { body: hash_including(type: 'authors', meta: { id: author.id, name: author.name }) }
        url = %r{api.lateral.io/documents/#{item.id}/tags/#{author.hash_id}$}
        expect(WebMock).to have_requested(:post, url).with(expected_request)
      end
    end

    it 'creates tag in the api from category' do
      item = FactoryGirl.create :item
      stub_request(:any, %r{api.lateral.io/documents/#{item.id}/tags/feed_sources_.*$}).to_return body: ''
      item.send_to_api(@key)
      feed_source = item.feed_source
      url = %r{api.lateral.io/documents/#{item.id}/tags/feed_sources_#{feed_source.id}$}
      expected_request = { body: hash_including(type: 'sources', meta: { id: feed_source.id, name: feed_source.name }) }
      expect(WebMock).to have_requested(:post, url).with(expected_request)
    end

    it 'handles an error from the API' do
      stub_request(:any, %r{api.lateral.io/documents/\d+$}).to_return body: '{ "message": "less than 4 words recognized" }',
                                                                  status: 406
      @item.send_to_api(@key)
      @item.reload
      expect(@item.sent_to_api).to eq(true)
      expect(@item.rejected_by_api).to eq(true)
      expect(@item.error).to eq("{ \"message\": \"less than 4 words recognized\" }")
    end
  end

  describe '#create' do
    it 'errors if creating a duplicate' do
      item = FactoryGirl.create :item
      expect do
        FactoryGirl.create :item, feed_source: item.feed_source, guid: item.guid
      end.to raise_exception(ActiveRecord::RecordNotUnique)
    end
  end
end
