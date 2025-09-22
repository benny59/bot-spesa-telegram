require_relative 'spec_helper'

describe OpenFoodFactsClient do
  describe '.fetch_product_info' do
    it 'returns nil when product not found' do
      stub_request(:get, /world.openfoodfacts.org/).to_return(status: 200, body: '{"status":0}')
      expect(OpenFoodFactsClient.fetch_product_info('0000000000')).to be_nil
    end

    it 'returns product data and nutriments when found' do
      body = {
        status: 1,
        product: {
          product_name: 'Spec Product',
          nutriments: {
            'energy-kcal_100g' => 200,
            'fat_100g' => 8,
            'proteins_100g' => 5
          }
        }
      }.to_json

      stub_request(:get, /world.openfoodfacts.org/).to_return(status: 200, body: body)
      res = OpenFoodFactsClient.fetch_product_info('1234567890')
      expect(res).to be_a(Hash)
      expect(res[:ok]).to be true
      expect(res[:data]).to be_a(Hash)
      expect(res[:data]['name'] || res[:data]['product_name']).to eq('Spec Product')
      expect(res[:data]['nutriments']).to be_a(Hash)
    end
  end
end