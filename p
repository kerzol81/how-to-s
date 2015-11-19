"""
Make the following changes to your compute_bill function:

    While you loop through each item of food, only add the price of the item to total if the item's stock count is greater than zero.
    If the item is in stock and after you add the price to the total, subtract one from the item's stock count.
"""

shopping_list = ["banana", "orange", "apple"]

stock = {
    "banana": 6,
    "apple": 0,
    "orange": 32,
    "pear": 15
}
    
prices = {
    "banana": 4,
    "apple": 2,
    "orange": 1.5,
    "pear": 3
}

# Write your code below!
def compute_bill(food):
    total = 0
    for i in food:
        if stock[i] > 0:
            total = total + prices[i]
    return total
