class Brand < ApplicationRecord
  has_many :customers
  has_many :tickets
end
