# encoding: utf-8
# author: Boris Barroso
# email: boriscyber@gmail.com
class AccountLedger < ActiveRecord::Base
  acts_as_org

  include ActionView::Helpers::NumberHelper

  # callbacks
  after_initialize :set_defaults
  before_save      :set_income              
  before_save      :set_creator_id
  before_save      :set_currency
  after_save       :update_payment,         :if => :payment?
  after_save       :update_account_balance, :if => :conciliation?
  after_destroy    :destroy_payment,        :if => :payment?

  # relationships
  belongs_to :account
  belongs_to :payment
  belongs_to :contact
  belongs_to :currency
  belongs_to :transaction

  belongs_to :creator,  :class_name => 'User'
  belongs_to :approver, :class_name => 'User'

  attr_accessor  :payment_destroy, :to_account, :to_exchange_rate, :to_amount_currency
  attr_reader    :transference
  attr_protected :conciliation

  # validations
  validates_presence_of :account_id, :date, :reference, :amount
  validates_numericality_of :amount, :greater_than => 0, :unless => :conciliation?
  validate :valid_organisation_account

  # transference
  with_options :if => :transference do |al|
    al.validate :validate_to_account
    al.validate :validate_to_exchange_rate
  end

  # delegates
  delegate :name, :number, :type, :to => :account, :prefix => true
  delegate :amount, :interests_penalties, :date, :state, :to => :payment, :prefix => true
  delegate :name, :symbol, :to => :currency, :prefix => true

  # scopes
  scope :pendent,     where(:conciliation => false)
  scope :conciliated, where(:conciliation => true)

  # Updates the conciliation state
  def conciliate_account
    self.approver_id  = UserSession.current_user.id
    self.conciliation = true
    self.save
  end

  # Returns a scope based on the option
  def self.get_by_option(option)
    ledgers = includes(:payment, :transaction, :contact) 
    case option
    when 'false' then ledgers.pendent
    when 'true' then ledgers.conciliated
    else
      ledgers
    end
  end

  # Creates transference
  def create_transference
    @transference         = true
    self.reference        = 'Transferencia'
    self.to_exchange_rate = to_exchange_rate.to_f
    if valid?
      to_amount_currency = to_exchange_rate.round(4) * amount

      AccountLedger.transaction do
        txt = ""
        unless account_to.currency_id == account.currency_id
          txt = ", tipo de cambio 1 #{account.currency} = #{number_to_currency to_exchange_rate, :precision => 4}" 
          txt << " #{account.currency_plural}"
        end

        self.income      = false
        self.description = "Transferencia a cuenta #{@ac2}#{txt}"

        ac2             = AccountLedger.new(self.attributes)
        ac2.account_id  = to_account
        ac2.income      = true
        ac2.amount      = amount * to_exchange_rate
        ac2.description = "Transferencia desde cuenta #{account},#{txt}"

        ac2.account_ledger_id = id
        
        raise ActiveRecord::Rollback unless self.save
        raise ActiveRecord::Rollback unless ac2.save
        raise ActiveRecord::Rollback unless self.update_attribute(:account_ledger_id, ac2.id)
      end
      true
    else
      false
    end
  end

  def show_exchange_rate?
    if to_account.present?
      if errors[:to_account].blank? and account.currency_id != account_to.currency_id
        true
      else
        false
      end
    else
      false
    end
  end

private
  
  # returns the account_to, using to_account id
  def account_to
    if to_account.present? and @acc_to.nil?
      @acc_to = Account.org.where(:id => to_account)
      if @acc_to.any?
        @acc_to = @acc_to.first
      else
        false
      end
    else
      @acc_to
    end
  end

  # validates the account
  def validate_to_account
    unless account_to
      errors.add(:to_account, "Debe seleccionar una cuenta válida")
    else
      self.to_exchange_rate = 1 if account_to.currency_id == account.currency_id
    end
  end

  # validates that the exchange rate is set
  def validate_to_exchange_rate
    if account_to and account.currency_id != account_to.currency_id
      if to_exchange_rate <= 0
        errors.add(:to_exchange_rate, "Debe ingresar un valor mayor que 0")
      end
    end
  end

  def set_defaults
    self.date ||= Date.today
    self.conciliation = self.conciliation.nil? ? false : conciliation
  end

  def payment?
    payment_id.present? and conciliation?
  end

  #  set the amount depending if income or outcome
  def set_income
    self.income = false if income.blank?
    if (not(income) and amount > 0) or (income and amount < 0)
      self.amount = -1 * amount
    end
    true
  end

  def set_currency
    self.currency_id = account.currency_id if account_id.present?
  end

  # Updates the payment state, without triggering any callbacks
  def update_payment
    if conciliation == true and payment.present? and not(payment_state == 'paid')
      payment.state = 'paid'
      payment.set_updated_account_ledger(true)
      payment.save(:validate => false)
    end
  end

  # Updates the total amount for the account
  def update_account_balance
    self.account.total_amount = (self.account.total_amount + amount)
    self.account.save
  end

  def payment?
    payment_id.present?
  end

  # destroys a payment, in case the payment calls for destroying the account_ledger
  # the if payment.present? will control if the payment was not already destroyed
  def destroy_payment
    payment.destroy if payment.present?
  end

  def valid_organisation_account
    unless Account.org.map(&:id).include?(account_id)
      logger.warn "El usuario #{UserSession.user_id} trato de hackear account_ledger"
      errors.add(:base, "Ha seleccionado una cuenta inexistente regrese a la cuenta")
    end
  end

  def set_creator_id
    self.creator_id = UserSession.current_user.id
  end
end
