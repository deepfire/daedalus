Feature: Switching Between Wallets

  Background:
    Given I have selected English language

  Scenario Outline: Using the Sidebar to Switch Wallets
    Given I have the following wallets:
    | name   |
    | first  |
    | second |
    | third  |
    And I am on the "<START>" wallet "summary" screen
    And The sidebar shows the "wallets" category
    When I click on the "<TARGET>" wallet in the sidebar
    Then I should be on the "<TARGET>" wallet "summary" screen

    Examples:
    | START  | TARGET |
    | first  | second |
    | second | third  |
