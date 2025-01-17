# frozen_string_literal: true

module RuboCop
  module Cop
    module Rails
      # This cop checks direct manipulation of ActiveModel#errors as hash.
      # These operations are deprecated in Rails 6.1 and will not work in Rails 7.
      #
      # @safety
      #   This cop is unsafe because it can report `errors` manipulation on non-ActiveModel,
      #   which is obviously valid.
      #   The cop has no way of knowing whether a variable is an ActiveModel or not.
      #
      # @example
      #   # bad
      #   user.errors[:name] << 'msg'
      #   user.errors.messages[:name] << 'msg'
      #
      #   # good
      #   user.errors.add(:name, 'msg')
      #
      #   # bad
      #   user.errors[:name].clear
      #   user.errors.messages[:name].clear
      #
      #   # good
      #   user.errors.delete(:name)
      #
      class DeprecatedActiveModelErrorsMethods < Base
        include RangeHelp
        extend AutoCorrector

        MSG = 'Avoid manipulating ActiveModel errors as hash directly.'
        AUTOCORECTABLE_METHODS = %i[<< clear].freeze

        MANIPULATIVE_METHODS = Set[
          *%i[
            << append clear collect! compact! concat
            delete delete_at delete_if drop drop_while fill filter! keep_if
            flatten! insert map! pop prepend push reject! replace reverse!
            rotate! select! shift shuffle! slice! sort! sort_by! uniq! unshift
          ]
        ].freeze

        def_node_matcher :receiver_matcher_outside_model, '{send ivar lvar}'
        def_node_matcher :receiver_matcher_inside_model, '{nil? send ivar lvar}'

        def_node_matcher :any_manipulation?, <<~PATTERN
          {
            #root_manipulation?
            #root_assignment?
            #messages_details_manipulation?
            #messages_details_assignment?
          }
        PATTERN

        def_node_matcher :root_manipulation?, <<~PATTERN
          (send
            (send
              (send #receiver_matcher :errors) :[] ...)
            MANIPULATIVE_METHODS
            ...
          )
        PATTERN

        def_node_matcher :root_assignment?, <<~PATTERN
          (send
            (send #receiver_matcher :errors)
            :[]=
            ...)
        PATTERN

        def_node_matcher :messages_details_manipulation?, <<~PATTERN
          (send
            (send
              (send
                (send #receiver_matcher :errors)
                {:messages :details})
                :[]
                ...)
              MANIPULATIVE_METHODS
            ...)
        PATTERN

        def_node_matcher :messages_details_assignment?, <<~PATTERN
          (send
            (send
              (send #receiver_matcher :errors)
              {:messages :details})
            :[]=
            ...)
        PATTERN

        def on_send(node)
          any_manipulation?(node) do
            add_offense(node) do |corrector|
              next unless AUTOCORECTABLE_METHODS.include?(node.method_name)

              autocorrect(corrector, node)
            end
          end
        end

        private

        def autocorrect(corrector, node)
          receiver = node.receiver

          if receiver.receiver.method?(:messages)
            corrector.remove(receiver.receiver.loc.dot)
            corrector.remove(receiver.receiver.loc.selector)
          end

          range = offense_range(node, receiver)
          replacement = replacement(node, receiver)

          corrector.replace(range, replacement)
        end

        def offense_range(node, receiver)
          range_between(receiver.receiver.source_range.end_pos, node.source_range.end_pos)
        end

        def replacement(node, receiver)
          key = receiver.first_argument.source

          case node.method_name
          when :<<
            value = node.first_argument.source

            ".add(#{key}, #{value})"
          when :clear
            ".delete(#{key})"
          end
        end

        def receiver_matcher(node)
          model_file? ? receiver_matcher_inside_model(node) : receiver_matcher_outside_model(node)
        end

        def model_file?
          processed_source.buffer.name.include?('/models/')
        end
      end
    end
  end
end
