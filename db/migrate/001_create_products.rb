require_relative '../../app/models/product'

Product.create_table!
puts "products table created (or already exists) in spesa.db"