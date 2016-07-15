# TODO
# Implement min volume btc & eth for bot to function


module Bot

  ETH_SELL_RANGE  = { min: 0.0161, max: 1 }
  ETH_BUY_RANGE   = { min: 0.0151, max: 0.0159 }
  CURRENCY        = "BTC_ETH"

  # return current ticker hash for currency
  def self.ticker
    JSON.parse(Poloniex.ticker)[CURRENCY]
  end

  # 2D array of bids/asks
  def self.order_book
    JSON.parse Poloniex.order_book(CURRENCY)
  end

  # Open orders from self
  def self.my_orders
    JSON.parse Poloniex.open_orders(CURRENCY)
  end

  def self.last_price
    self.ticker['last'].to_f
  end

  def self.day_high
    self.ticker['high24hr'].to_f
  end

  def self.day_low
    self.ticker['low24hr'].to_f
  end

  def self.asks
    self.order_book['asks'].map(&:to_f)
  end

  def self.bids
    self.order_book['bids'].map(&:to_f)
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

  # Trading

  # have btc to buy eth
  def self.can_buy?
    btc_balance = JSON.parse(Poloniex.balances)['BTC'].to_f
    btc_balance > 0.1
  end

  # have eth to sell btc
  def self.can_sell?
    eth_balance = JSON.parse(Poloniex.balances)['ETH'].to_f
    eth_balance > 0.1
  end

  def self.prices_within_range?(order_type)
    last_price = self.last_price
    case order_type
    when 'buy'
      puts "Last price was: #{last_price}"
      puts "Max buy price set at: #{ETH_BUY_RANGE[:max]}"
      within_range = last_price <= ETH_BUY_RANGE[:max]
      puts "Within buying range: #{within_range}"
      return within_range
    when 'sell'
      puts "Last price was: #{last_price}"
      puts "Minimum sell price set at: #{ETH_BUY_RANGE[:min]}"
      within_range = last_price >= ETH_SELL_RANGE[:min]
      puts "Within selling range: #{within_range}"
      return within_range
    else
      raise "'order_type' can be either 'buy' or 'sell'"
    end
  end

  def self.cancel_orders(order_type)
    raise "'order_type' can be either 'buy' or 'sell'" unless ['buy', 'sell'].include? order_type

    my_orders = self.my_orders
    buy_orders = my_orders.select { |o| o['type'] == 'buy' }
    sell_orders = my_orders.select { |o| o['type'] == 'sell' }
    orders_to_cancel = order_type == 'buy' && buy_orders || sell_orders

    orders_to_cancel.each do |order|
      cancel = JSON.parse(Poloniex.cancel_order(CURRENCY, order['orderNumber']))
      raise cancel['error'] if cancel['success'] == 0
      puts cancel['message'] if cancel['success'] == 1
    end
  end

  # TODO
  # def self.info
  #   bids_avg = self.bids_average
  #   asks_avg = self.asks_average
  # end

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
