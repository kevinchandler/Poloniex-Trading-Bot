# TODO
# Implement min volume btc & eth for bot to function



module Bot

  ETH_SELL_RANGE  = [0.0161..1]
  ETH_BUY_RANGE   = [0.0151..0.0159]
  CURRENCY        = "BTC_ETH"

  # return current ticker hash for currency
  def self.ticker
    JSON.parse(Poloniex.ticker)[CURRENCY]
  end

  # 2D array of bids/asks
  def self.orders
    JSON.parse Poloniex.order_book(CURRENCY)
  end

  # Current open orders on account
  def self.current_orders
    JSON.parse Poloniex.open_orders(CURRENCY)
  end


  def self.day_high
    self.ticker['high24hr']
  end

  def self.day_low
    self.ticker['low24hr']
  end

  def self.asks
    self.orders['asks']
  end

  def self.bids
    self.orders['bids']
  end

  def self.bids_average
    bids = self.bids
    bid_prices = []
    bids.each { |bid| bid_prices << bid[0] }
    self.calculate_average(bid_prices)
  end

  def self.bids_volume
    bids = self.bids
    bid_prices = []
    bids.each { |bid| bid_prices << bid[1] }
    bid_prices.reduce(:+)
  end

  def self.asks_average
    asks = self.asks
    ask_prices = []
    asks.each { |bid| ask_prices << bid[0] }
    self.calculate_average(ask_prices)
  end

  def self.asks_volume
    asks = self.asks
    ask_prices = []
    asks.each { |bid| ask_prices << bid[1] }
    ask_prices.reduce(:+)
  end

  def self.info
    bids_avg = self.bids_average
    asks_avg = self.asks_average

    binding.pry
  end

  private

  def self.calculate_average(prices)
    prices = self.remove_outliers(prices.map(&:to_f), true)
    avg = (prices.reduce(:+).to_f / prices.size.to_f) rescue nil
  end

  def self.calculate_median(prices)
    prices = self.remove_outliers(prices.map(&:to_f), true)
    len = prices.length
    median = (prices[(len - 1) / 2] + prices[len / 2]) / 2.0 rescue nil
    median
  end

  def self.remove_outliers(prices, remove_minor_outliers=false)
      return prices unless prices.kind_of?(Array) && prices.any?

      all_prices = prices.sort!
      original_prices = prices
      prices = all_prices.dup
      lower_quad = prices.shift(prices.length / 2)
      higher_quad = prices
      lower_quad_median = (lower_quad[(lower_quad.length - 1) / 2] + lower_quad[lower_quad.length / 2]) / 2.0 rescue nil
      higher_quad_median = (higher_quad[(higher_quad.length - 1) / 2] + higher_quad[higher_quad.length / 2]) / 2.0 rescue nil

      return original_prices unless lower_quad_median && higher_quad_median

      interquartile_range = higher_quad_median - lower_quad_median
      outer_fences_range = interquartile_range * 3
      outer_fences_min = (lower_quad_median - outer_fences_range).to_f
      outer_fences_max = (higher_quad_median + outer_fences_range).to_f
      major_outliers = all_prices.select { |price| price > outer_fences_max || price < outer_fences_min }
      if remove_minor_outliers
        inner_fences_range = interquartile_range * 1.5
        inner_fences_min = (lower_quad_median - inner_fences_range).to_f
        inner_fences_max = (higher_quad_median + inner_fences_range).to_f
        prices = all_prices.reject { |price| (price > outer_fences_max || price < outer_fences_min) || (price > inner_fences_max || price < inner_fences_min) }
      else
        prices = all_prices.reject { |price| price > outer_fences_max || price < outer_fences_min }
      end

      prices
  rescue => e
    puts e
  end



end
