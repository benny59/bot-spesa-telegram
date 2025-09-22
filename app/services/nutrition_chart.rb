require 'gruff'

module NutritionChart
  # data: hash { 'Energy' => value, 'Fat' => value, ... }
  # filepath: full path where to save PNG
  def self.generate_radar(data, filepath)
    labels = {}
    data.keys.each_with_index do |k, i|
      labels[i] = k
    end

    g = Gruff::Spider.new(800)
    g.title = 'Nutrients bought'
    g.theme = {
      colors: ['#aedaa9', '#12a8a8'],
      marker_color: '#dddddd',
      background_colors: %w[#ffffff #ffffff]
    }

    # Gruff::Spider expects arrays of values per dataset; use single dataset
    values = data.values.map(&:to_f)
    g.data('bought', values)
    g.labels = labels
    g.write(filepath)
    filepath
  end
end