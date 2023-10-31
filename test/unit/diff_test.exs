defmodule DiffTest do
  use ExUnit.Case
  alias LambdaEthereumConsensus.Utils.Diff

  describe "Basic comparison" do
    test "shows both sides if different" do
      assert Diff.diff(1, 2) == %{left: 1, right: 2}
    end

    test "shows :unchanged if they are the same" do
      assert Diff.diff(1, 1) == :unchanged
    end
  end

  describe "List comparison" do
    test "shows added_left if the left list has more elements" do
      assert Diff.diff([1, 2, 3, 4], [1, 2]) == %{added_left: [3, 4]}
    end

    test "shows added_right if the right list has more elements" do
      assert Diff.diff([1, 2], [1, 2, 3, 4]) == %{added_right: [3, 4]}
    end

    test "shows changes for equally large lists" do
      assert Diff.diff([1, 2, 3, 4], [1, 7, 3, 10]) == %{
               changed: [{1, %{left: 2, right: 7}}, {3, %{left: 4, right: 10}}]
             }
    end

    test "shows changes and added_right if both are present" do
      assert Diff.diff([1], [3, 4]) == %{changed: [{0, %{left: 1, right: 3}}], added_right: [4]}
    end

    test "is :unchanged if the lists are equal" do
      assert Diff.diff([1, 2, 3], [1, 2, 3]) == :unchanged
    end

    test "is :unchanged when both lists are empty" do
      assert Diff.diff([], []) == :unchanged
    end

    test "shows the diff for lists in lists" do
      assert Diff.diff([:a, [1, 2], :b], [:a, [1, 4, 3]]) == %{
               added_left: [:b],
               changed: [{1, %{added_right: [3], changed: [{1, %{left: 2, right: 4}}]}}]
             }
    end
  end

  describe "Maps comparison" do
    test "shows :unchanged if they are the same" do
      assert Diff.diff(%{}, %{}) == :unchanged
      assert Diff.diff(%{a: 1, b: 2}, %{a: 1, b: 2}) == :unchanged
      assert Diff.diff(%{a: [1, 2]}, %{a: [1, 2]}) == :unchanged
      assert Diff.diff(%{a: %{a: 1, b: 2}}, %{a: %{a: 1, b: 2}}) == :unchanged
    end

    test "shows added_left if the left map has more keys" do
      assert Diff.diff(%{a: 1, b: 2}, %{a: 1}) == %{added_left: [b: 2]}
    end

    test "shows added_right if the right map has more keys" do
      assert Diff.diff(%{a: 1}, %{a: 1, b: 2}) == %{added_right: [b: 2]}
    end
  end
end
