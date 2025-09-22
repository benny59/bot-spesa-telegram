# lightweight radar chart generator using ChunkyPNG (no native image libs required)
require 'chunky_png'
require 'tmpdir'

module NutritionChart
  # data: hash { 'Energy (kcal)' => value, ... }
  # filepath: where to save PNG (returns filepath)
  def self.generate_radar(data, filepath)
    keys = data.keys
    values = data.values.map(&:to_f)
    return nil if keys.empty?

    size = 800
    cx = cy = size / 2
    margin = 80
    radius = (size / 2) - margin
    steps = 5

    max_value = values.max
    max_value = 1 if max_value <= 0

    img = ChunkyPNG::Image.new(size, size, ChunkyPNG::Color::WHITE)
    axis_color = ChunkyPNG::Color.rgba(200, 200, 200, 255)
    grid_color = ChunkyPNG::Color.rgba(240, 240, 240, 255)
    line_color = ChunkyPNG::Color.rgba(40, 120, 200, 255)
    dot_color  = ChunkyPNG::Color.rgba(40, 120, 200, 255)
    text_color = ChunkyPNG::Color.rgba(60, 60, 60, 255)

    n = keys.size
    angles = (0...n).map { |i| -Math::PI / 2.0 + 2.0 * Math::PI * i / n }

    pts_for = lambda do |scale|
      angles.map do |a|
        x = cx + Math.cos(a) * radius * scale
        y = cy + Math.sin(a) * radius * scale
        [x.round, y.round]
      end
    end

    # draw concentric polygon grid
    (1..steps).each do |s|
      poly = pts_for.call(s.to_f / steps)
      poly.each_with_index do |p, i|
        q = poly[(i + 1) % poly.length]
        img.line(p[0], p[1], q[0], q[1], grid_color)
      end
    end

    # draw axes
    angles.each do |a|
      ex = cx + Math.cos(a) * radius
      ey = cy + Math.sin(a) * radius
      img.line(cx, cy, ex.round, ey.round, axis_color)
    end

    # label placeholders (no TTF rendering)
    keys.each_with_index do |k, i|
      a = angles[i]
      lx = (cx + Math.cos(a) * (radius + 28)).round
      ly = (cy + Math.sin(a) * (radius + 28)).round
      0.upto(2) { |dx| 0.upto(2) { |dy| img[lx + dx, ly + dy] = text_color } }
    end

    # compute and draw data polygon
    scaled = values.map { |v| [v / max_value, 0.0].max }
    data_pts = scaled.each_with_index.map do |s, i|
      a = angles[i]
      [(cx + Math.cos(a) * radius * s).round, (cy + Math.sin(a) * radius * s).round]
    end

    data_pts.each_with_index do |p, i|
      q = data_pts[(i + 1) % data_pts.length]
      img.line(p[0], p[1], q[0], q[1], line_color)
    end

    data_pts.each { |p| draw_filled_circle(img, p[0], p[1], 4, dot_color) }

    put_text_placeholder(img, "Nutrients bought", cx, 20, text_color)

    img.save(filepath)
    filepath
  end

  private

  def self.draw_filled_circle(img, cx, cy, r, color)
    x0 = cx - r; x1 = cx + r; y0 = cy - r; y1 = cy + r
    (x0..x1).each do |x|
      (y0..y1).each do |y|
        dx = x - cx; dy = y - cy
        img[x, y] = color if dx * dx + dy * dy <= r * r
      end
    end
  end

  def self.put_text_placeholder(img, _text, x, y, color)
    0.upto(120) do |dx|
      0.upto(10) do |dy|
        img[x - 60 + dx, y + dy] = color if dx % 6 != 0
      end
    end
  end
end