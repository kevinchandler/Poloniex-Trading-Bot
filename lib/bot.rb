# TODO
# Estimated value of holdings: $403.04 USD / 0.60625362 BTC
# 8:37pm friday 7/15 Estimated value of holdings: $383.60 USD / 0.57275545 BTC

# Get last buy and sell prices and set Order.last_xxx_price
# more clear logs
# clean up code
# bug cancelling buy order?

class Numeric
  def percent_of(n)
    self.to_f / n.to_f * 100.0
  end
end


class Order
  attr_accessor :last_buy_price, :last_sell_price

  def initialize
    @last_buy_price = nil
    @last_sell_price = nil
  end
end



module Bot

  ETH_SELL_RANGE      = { min: 0.0145, max: 1 }
  ETH_BUY_RANGE       = { min: 0.0151, max: 0.019 }
  CURRENCY            = "BTC_ETH"
  MIN_GAIN_PERCENTAGE = 0.25
  MAX_LOSS_PERCENTAGE = -0.50
  ORDER               = Order.new

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
    orders = JSON.parse Poloniex.open_orders(CURRENCY)
    if orders && orders.kind_of?(JSON) && orders['error']
      raise orders['error']
    end
    return orders
  end

  def self.cancel_orders(order_type)
    raise "'order_type' can be either 'buy' or 'sell'" unless ['buy', 'sell'].include? order_type

    my_orders = self.my_orders
    buy_orders = my_orders.select { |o| o['type'] == 'buy' }
    sell_orders = my_orders.select { |o| o['type'] == 'sell' }
    orders_to_cancel = order_type == 'buy' && buy_orders || sell_orders

    orders_to_cancel.each do |order|
      begin
        self.cancel_order(order)
      rescue => e
        puts "cancel_orders"
        puts e
      end
    end
  end

  def self.cancel_order(order)
    cancel = JSON.parse(Poloniex.cancel_order(CURRENCY, order['orderNumber']))
    if cancel && cancel.kind_of?(JSON) && cancel['error']
      raise cancel['error']
    end
    self.log "cancel_order: #{cancel['message']}"
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
    self.order_book['asks'].map! { |ask| [ask[0].to_f, ask[1].to_f] }
  end

  def self.bids
    self.order_book['bids'].map! { |bid| [bid[0].to_f, bid[1].to_f] }
  end

  def self.balance(currency)
     JSON.parse(Poloniex.balances)[currency.upcase]
  end

  # Trading

  def self.set_trading_data
    trades = JSON.parse(Poloniex.trade_history("BTC_ETH"))
    last_buy_price = trades.select { |t| t['type'] == 'buy' }.first['rate'].to_f
    last_sell_price = trades.select { |t| t['type'] == 'sell' }.first['rate'].to_f
    ORDER.last_sell_price = last_sell_price
    ORDER.last_buy_price = last_buy_price

    if ORDER.last_sell_price.nil? || ORDER.last_buy_price.nil?
      raise "last buy or last sell prices not set"
    end
  end

  def self.trade
    while true
      begin
        self.set_trading_data
        puts "**********************"
        self.log "Starting trade session"

        my_orders = self.my_orders

        my_buys = my_orders.select { |order| order['type'] == 'buy' }
        my_sells = my_orders.select { |order| order['type'] == 'sell' }
        my_current_bid_price = my_buys.map { |buy| buy['rate'].to_f }.min
        my_current_ask_price = my_sells.map { |sell| sell['rate'].to_f }.min
        optimal_buy_price = self.optimal_price_to('buy')
        optimal_sell_price = self.optimal_price_to('sell')

        # BUYING

        # Cancel buy orders if we should be buying for a lower price
        self.log "Should we cancel any outstanding buy orders?"
        if my_current_bid_price && my_current_bid_price > optimal_buy_price
          begin
            cancel = self.cancel_orders 'buy'
            self.log "canceling buy orders"
            sleep 1
          rescue => e
            self.log e.backtrace
          end
        end

        if self.can_buy?
          begin
            if self.should_buy?(optimal_buy_price)
              btc_balance = BigDecimal(self.balance('BTC'))
              amount_to_buy = (btc_balance / optimal_buy_price).round(3)
              amount_to_buy = amount_to_buy / [1,2,3].sample
              buy = JSON.parse(Poloniex.buy(CURRENCY, optimal_buy_price, amount_to_buy))
              unless buy['error']
                self.log "Placing buy order for #{amount_to_buy} ETH at #{optimal_buy_price} each"
                self.log buy
                self.log "Last buy order was for #{ORDER.last_buy_price}"
                self.log "Last sell order was for #{ORDER.last_sell_price}"
                ORDER.last_buy_price = optimal_buy_price
                sleep 1
              end
            else
              self.log "profit/loss not enough to buy"
            end
          rescue => e
            self.log e
          end
        end


        # SELLING

        # Cancel sell orders if we should be selling for a higher price
        self.log "Should we cancel any outstanding sell orders?"
        if my_current_ask_price && my_current_ask_price > optimal_sell_price
          begin
            cancel = self.cancel_orders 'sell'
            self.log "canceling sell orders"
            self.log JSON.parse(cancel)
            sleep 1
          rescue => e
            self.log e
          end
        end

        if self.can_sell?
          begin
            if should_sell?(optimal_sell_price)
              eth_balance = BigDecimal(self.balance('ETH'))
              amount_to_sell = eth_balance / [1,2,3].sample
              sell = JSON.parse(Poloniex.sell(CURRENCY, optimal_sell_price, amount_to_sell))
              unless sell['error']
                self.log "Placing sell order for #{eth_balance} ETH at #{optimal_sell_price} each"
                self.log sell
                self.log "Last sell order was for: #{ORDER.last_sell_price}"
                self.log "Last buy order was for #{ORDER.last_buy_price}"
                ORDER.last_sell_price = optimal_sell_price
                sleep 1
              end
            else
              self.log "profit/loss not enough to sell"
            end
          rescue => e
            self.log e
          end
        end

        self.log "Ending trade session"
        sleep 1.5
      rescue => e
        self.log e.backtrace
      end
    end


  end

  def self.should_sell?(optimal_price_to_sell)
    pct_diff = self.calculate_percentage_diff optimal_price_to_sell, ORDER.last_buy_price
    should_sell = pct_diff >= MIN_GAIN_PERCENTAGE || pct_diff <= MAX_LOSS_PERCENTAGE

    self.log "Optimal sell price: #{optimal_price_to_sell}"
    self.log "Last buy price: #{ORDER.last_buy_price}"
    self.log "Sell % diff: #{pct_diff}"
    self.log "Selling? #{should_sell}"

    should_sell
  end

  def self.should_buy?(optimal_price_to_buy)
    # difference between my last sell price and the optimal buy price
    pct_diff = self.calculate_percentage_diff ORDER.last_sell_price, optimal_price_to_buy

    # buy if we can gain enough or accept a loss
    should_buy = pct_diff >= MIN_GAIN_PERCENTAGE || pct_diff <= MAX_LOSS_PERCENTAGE

    # unless should_buy
      # only give us output if we're not buying
      self.log "Optimal buy price: #{optimal_price_to_buy}"
      self.log "Last sell price: #{ORDER.last_sell_price}"
      self.log "Buy % diff: #{pct_diff}"
      self.log "Buy: #{should_buy}"
    # end

    should_buy
  end

  # have btc to buy eth
  def self.can_buy?
    btc_balance = self.balance('BTC').to_f
    has_enough = btc_balance > self.optimal_price_to('buy')
    sleep 0.25
    self.prices_within_range?('buy') && has_enough
  end

  # have eth to sell btc
  def self.can_sell?
    eth_balance = self.balance('ETH').to_f
    has_enough = eth_balance > self.optimal_price_to('sell')
    sleep 0.25
    self.prices_within_range?('sell') && has_enough
  end

  def self.prices_within_range?(order_type)
    last_price = self.last_price
    case order_type
    when 'buy'
      return last_price <= ETH_BUY_RANGE[:max]
    when 'sell'
      return last_price >= ETH_SELL_RANGE[:min]
    else
      raise "'order_type' can be either 'buy' or 'sell'"
    end
  end

  def self.optimal_price_to(order_type)
    orders = case order_type
    when 'buy'
      self.bids
    when 'sell'
      self.asks
    else
      raise "'order_type' can be either 'buy' or 'sell'" unless ['buy', 'sell'].include? order_type
    end

    price = orders.sort_by { |order| order[1] }.reverse.first(rand(4..8)).sample[0]
    self.log "Optimal #{order_type.upcase} price: #{price}"
    price
  end

  # def self.bids_average
  #   bids = self.bids
  #   bid_prices = []
  #   bids.each { |bid| bid_prices << bid[0] }
  #   self.calculate_average(bid_prices)
  # end
  #
  # def self.bids_volume
  #   bids = self.bids
  #   bid_prices = []
  #   bids.each { |bid| bid_prices << bid[1] }
  #   bid_prices.reduce(:+)
  # end
  #
  # def self.asks_average
  #   asks = self.asks
  #   ask_prices = []
  #   asks.each { |bid| ask_prices << bid[0] }
  #   self.calculate_average(ask_prices)
  # end
  #
  # def self.asks_volume
  #   asks = self.asks
  #   ask_prices = []
  #   asks.each { |bid| ask_prices << bid[1] }
  #   ask_prices.reduce(:+)
  # end

  private

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
    puts "\n"
    puts msg
  end

end
