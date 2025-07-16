
import requests
from pathlib import Path
from pprint import pprint

def test_endpoint(url, method="post", file_path=None, params=None):
    try:
        if method == "post":
            # Using Path to handle the file path
            files = {"file": open(Path(file_path), "rb")}
            response = requests.post(url, files=files)
        else:
            response = requests.get(url, params=params)
        
        response.raise_for_status()
        return response.json()
        
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    # Using raw string for Windows path
    test_file = "C:/Users/User/Desktop/Mewsage/Backend_Mewsage/Test_sound/B_ANI01_MC_FN_SIM01_103.wav"
    
    print("\n=== Testing File Upload ===")
    upload_result = test_endpoint(
        "http://localhost:8000/predict",
        method="post",
        file_path=test_file
    )
    pprint(upload_result, indent=2)
    
    print("\n=== Testing Local Path ===")
    local_result = test_endpoint(
        "http://localhost:8000/predict-local",
        method="get",
        params={"C:/Users/User/Desktop/Mewsage/Backend_Mewsage/Test_sound/B_ANI01_MC_FN_SIM01_103.wav": test_file}
    )
    pprint(local_result, indent=2)

    