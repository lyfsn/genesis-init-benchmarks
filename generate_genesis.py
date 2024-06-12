import json
import random
import os
import sys

def generate_random_address():
    return '0x' + ''.join(random.choices('0123456789abcdef', k=40))

def generate_random_balance():
    return hex(random.randint(1, 10**18))

def create_large_genesis(input_file, output_file, target_size):
    try:
        with open(input_file, 'r') as f:
            genesis = json.load(f)
    except Exception as e:
        print(f"Error reading {input_file}: {e}")
        return
    
    if "alloc" not in genesis:
        genesis["alloc"] = {}
    accounts = genesis["alloc"]

    current_size = len(json.dumps(genesis))

    def estimate_account_size():
        test_accounts = {generate_random_address(): {"balance": generate_random_balance()} for _ in range(100)}
        return len(json.dumps(test_accounts)) / 100

    average_account_size = estimate_account_size()
    estimated_total_accounts_needed = (target_size - current_size) // average_account_size

    def add_accounts(batch_size):
        new_accounts = {}
        for _ in range(batch_size):
            new_address = generate_random_address()
            new_balance = generate_random_balance()
            new_accounts[new_address] = {"balance": new_balance}
        return new_accounts

    batch_size = 10000 
    while current_size < target_size:
        accounts_to_add = add_accounts(batch_size)
        accounts.update(accounts_to_add)
        current_size += average_account_size * batch_size

        print(f"Current estimated size: {current_size / 1024 / 1024:.2f} MB")
        if current_size >= target_size:
            break

    genesis['alloc'] = accounts

    try:
        with open(output_file, 'w', encoding='utf-8') as out_file:
            json.dump(genesis, out_file, indent=2)
        actual_size = os.path.getsize(output_file)
        print(f"Generated {output_file} with actual size {actual_size / 1024 / 1024:.2f} MB")
    except Exception as e:
        print(f"Error writing to {output_file}: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python script.py <input_file> <output_file> <target_size_in_MB>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    try:
        target_size = float(sys.argv[3]) * 1024 * 1024  # Convert MB to bytes
    except ValueError:
        print("Target size must be a number")
        sys.exit(1)

    create_large_genesis(input_file, output_file, target_size)
