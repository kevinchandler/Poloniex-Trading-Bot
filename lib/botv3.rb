class Bot

  CURRENCY_PAIR = "BTC_ETH"
  SLEEP_TIME = { min: 0.5, max: 2, new_round: 300 }
  PERCENTAGES = { gain: 2.0, loss: -10 }
  PERCENTAGES[:gain]
  PERCENTAGES[:loss]


  def initialize
    @my_wallet      = { BTC: nil, ETH: nil }
    @my_last_price  = { buy: nil, sell: nil }
    @optimal_price  = { buy: nil, sell: nil }
  end

  def intialize_trading_session

    # set last buy/sell prices
    trades = JSON.parse(Poloniex.trade_history(CURRENCY_PAIR)) rescue nil
    raise "Unable to retrieve trading data" unless trades

    @my_last_price[:buy] = trades.select { |t| t['type'] == 'buy' }.first['rate'].to_f
    @my_last_price[:sell] = trades.select { |t| t['type'] == 'sell' }.first['rate'].to_f

    if @my_last_price[:sell].nil? || @my_last_price[:buy].nil?
      raise "Unable to set trading data"
    end

    sleep SLEEP_TIME[:max]

    # set wallet balances
    @my_wallet[:BTC] = my_balance("BTC")
    @my_wallet[:ETH] = my_balance("ETH")

    sleep SLEEP_TIME[:max]

    # cancel any outstanding orders
    cancel_orders 'buy'
    cancel_orders 'sell'

    sleep SLEEP_TIME[:max]

    # set optimal prices to buy / sell
    @optimal_price[:buy] = self.optimal_price_to('buy').to_f
    @optimal_price[:sell] = self.optimal_price_to('sell').to_f

    if @optimal_price[:sell].nil? || @optimal_price[:buy].nil?
      raise "Failed to set optimal buy/sell prices"
    end

    sleep SLEEP_TIME[:max]
  end


  def trade
    while true
      system 'clear'
      puts "**********************"
      puts "Starting Trade Session"
      puts "**********************"

      intialize_trading_session
      place_order 'sell' if has_balance?('sell') && should_sell?
      place_order 'buy' if has_balance?('buy') && should_buy?

      puts "Sleeping #{SLEEP_TIME[:new_round] / 60} minutes"
      sleep SLEEP_TIME[:new_round]
    end
  end

  protected

  def place_order(order_type)
    check_order_type order_type
    currency = currency_for order_type
    amount = @my_wallet[currency.to_sym] / @optimal_price[order_type.to_sym].round(2)
    retries = 0
    begin
      order = case order_type
      when 'buy'
        JSON.parse(Poloniex.buy(CURRENCY_PAIR, @optimal_price[order_type.to_sym], amount))
      when 'sell'
        JSON.parse(Poloniex.sell(CURRENCY_PAIR, @optimal_price[order_type.to_sym], amount))
      end
      error = order['error'] rescue nil
      raise error unless error.nil?
    rescue => e
      puts e.message
      puts "retrying to place #{order_type} order"
      retries += 1
      retry if retries < 10
    ensure
      sleep SLEEP_TIME[:min]
    end
  end

  def cancel_orders(order_type)
    check_order_type order_type

    orders = my_orders
    buys = orders.select { |o| o['type'] == 'buy' }
    sells = orders.select { |o| o['type'] == 'sell' }
    orders_to_cancel = order_type == 'buy' && buys || sells
    self.log "Canceling #{order_type.upcase} orders"

    cancel_order = -> (order) do
      begin
        cancel = JSON.parse(Poloniex.cancel_order(CURRENCY_PAIR, order['orderNumber']))
        if cancel && cancel.kind_of?(JSON) && cancel['error']
          raise cancel['error']
        end
      rescue => e
        puts "cancel_orders\n#{e}"
      ensure
        sleep SLEEP_TIME[:min]
      end
      true
    end

    orders_to_cancel.each  { |order| cancel_order.call order }
  end

  def should_sell?
    # Difference between my last BUY price and the optimal SELL price
    pct_diff = self.class.calculate_percentage_diff @optimal_price[:sell], @my_last_price[:buy]

    puts "Last buy price: #{@my_last_price[:buy]}"
    puts "Optimal sell price: #{@optimal_price[:sell]}"
    puts "PCT DIFF: #{pct_diff}"
    puts "Acceptable loss? #{(pct_diff <= PERCENTAGES[:loss])}"
    puts "Acceptable gain? #{(pct_diff >= PERCENTAGES[:gain])}"
    puts "---------------------"

    # SELL if we can gain enough or accept a loss
    (pct_diff >= PERCENTAGES[:gain]) || (pct_diff <= PERCENTAGES[:loss])
  end

  def should_buy?
    # Difference between my last SELL price and the optimal BUY price
    pct_diff = self.class.calculate_percentage_diff @my_last_price[:sell], @optimal_price[:buy]

    puts "Last sell price: #{@my_last_price[:sell]}"
    puts "Optimal buy price: #{@optimal_price[:buy]}"
    puts "PCT DIFF: #{pct_diff}"
    puts "Acceptable loss? #{(pct_diff <= PERCENTAGES[:loss])}"
    puts "Acceptable gain? #{(pct_diff >= PERCENTAGES[:gain])}"
    puts "---------------------"

    # BUY if we can gain enough or accept a loss
    (pct_diff >= PERCENTAGES[:gain]) || (pct_diff <= PERCENTAGES[:loss])
  end


  def has_balance?(order_type)
    check_order_type order_type
    currency = currency_for order_type
    @my_wallet[currency.to_sym] >= optimal_price_to(order_type)
  end

  # Open orders from self
  def my_orders
    orders = JSON.parse Poloniex.open_orders(CURRENCY_PAIR)
    if orders && orders.kind_of?(JSON) && orders['error']
      raise orders['error']
    end

    sleep SLEEP_TIME[:min]
    return orders
  end

  def my_current_bid_price
    my_buys = my_orders.select { |order| order['type'] == 'buy' }
    my_buys.map { |buy| buy['rate'].to_f }.max
  end

  def my_current_ask_price
    my_sells = my_orders.select { |order| order['type'] == 'sell' }
    my_sells.map { |sell| sell['rate'].to_f }.max
  end

  def optimal_price_to(order_type)
    orders = case order_type
    when 'buy'
      bids
    when 'sell'
      asks
    else
      raise "'order_type' can be either 'buy' or 'sell'" unless ['buy', 'sell'].include? order_type
    end

    # grab the prices of 15 most expensive orders and place order for the median
    prices = orders.sort_by { |order| order[1] }.reverse.first(15).map { |price, vol| price }
    self.class.calculate_median prices
  end

  def check_order_type(order_type)
    raise "'order_type' can be either 'buy' or 'sell'" unless ['buy', 'sell'].include? order_type
  end

  # ORDER BOOK
  def asks
    self.order_book['asks'].map { |ask| [ask[0].to_f, ask[1].to_f] }
  end

  def bids
    self.order_book['bids'].map { |bid| [bid[0].to_f, bid[1].to_f] }
  end

  # return current ticker hash for currency
  def ticker
    JSON.parse(Poloniex.ticker)[CURRENCY_PAIR]
  end

  # 2D array of bids/asks
  def order_book
    JSON.parse Poloniex.order_book(CURRENCY_PAIR)
  end

  def my_balance(currency)
    JSON.parse(Poloniex.balances)[currency.upcase].to_f
  end

  def currency_for(order_type)
    check_order_type order_type
    order_type == "buy" ? "BTC" : "ETH"
  end


  def self.calculate_percentage_diff(a, b)
    (((a - b) / a) * 100).round(2)
  end

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
    self.log e.backtrace
  end

  def self.log(msg)
    puts msg
  end

  def log(msg)
    puts msg
  end



end
