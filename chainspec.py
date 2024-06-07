import json
import random
import string
import os
import sys

def generate_random_address():
    return '0x' + ''.join(random.choices(string.hexdigits, k=40)).lower()

def generate_random_balance():
    return hex(random.randint(1, 10**18))

def create_large_chainspec(input_file, output_file, target_size):
    with open(input_file, 'r') as f:
        chainspec = json.load(f)

    current_size = os.path.getsize(input_file)
    accounts = chainspec.get('accounts', {})
    
    while current_size < target_size:
        new_address = generate_random_address()
        new_balance = generate_random_balance()
        accounts[new_address] = {"balance": new_balance}
        
        chainspec['accounts'] = accounts
        temp_json = json.dumps(chainspec, indent=2)
        current_size = len(temp_json.encode('utf-8'))

    with open(output_file, 'w') as f:
        f.write(temp_json)
    
    print(f"Generated {output_file} with size {current_size/1024/1024:.2f} MB")

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Usage: python script.py <input_file> <output_file> <target_size_in_MB>")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2]
    target_size = int(sys.argv[3]) * 1024 * 1024  # Convert MB to bytes

    create_large_chainspec(input_file, output_file, target_size)
