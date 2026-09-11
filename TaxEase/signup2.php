<?php
// Include your database connection file (assuming it's db.php)
session_start();
include('connect.php');

//$user_id = $_SESSION['user_id'];
if (isset($_SESSION['user_id'])) {
    $user_id = $_SESSION['user_id'];  // Get the user_id from the session
} else {
    // If user_id is not set, display an error or redirect back to the signup page
    die("Error: No user ID found. Please register again.");
}


// Check if form is submitted
if ($_SERVER["REQUEST_METHOD"] == "POST") {
    // Collect asset data from the form
    // $user_id = $_SESSION['user_id']; // Assuming this comes from a session or is passed dynamically
    $land_type = $_POST['land_type'];
    $land_amount = $_POST['land_amount'];
    $vehicle_type = $_POST['vehicle_type'];
    $vehicle_model = $_POST['vehicle_model'];
    $business_asset = $_POST['business_asset'];
    $business_type = $_POST['business_type'];

   
    $query = "INSERT INTO user_assets (user_id,land_type, land_amount, vehicle_type, vehicle_model, business_asset,business_type)
              VALUES (?,?,?,?,?,?,?)";

    $stmt = $conn->prepare($query);
    $stmt->bind_param("isdsss", $user_id, $land_type, $land_amount, $vehicle_type, $vehicle_model, $business_asset,$business_type);

    if ($stmt->execute()) {
       
        $user_query = "SELECT first_name, email FROM registered WHERE user_id = $user_id";
        $user_stmt = $conn->query($user_query); 
        
        if ($user_stmt) {
            // Fetch the result
            $result = $user_stmt->fetch_assoc();
            $first_name = $result['first_name'];
            $email = $result['email'];
        
            $_SESSION['first_name'] = $first_name;
            $_SESSION['email'] = $email;
        
            header('location:dashboard2.php');
            exit();
        }
        

    $stmt->close();
    $conn->close();
}
}
?>




<!DOCTYPE html>
<html lang="en">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Asset Information</title>
    <link href="//maxcdn.bootstrapcdn.com/bootstrap/4.1.1/css/bootstrap.min.css" rel="stylesheet" id="bootstrap-css">
    <script src="//maxcdn.bootstrapcdn.com/bootstrap/4.1.1/js/bootstrap.min.js"></script>
    <script src="//cdnjs.cloudflare.com/ajax/libs/jquery/3.2.1/jquery.min.js"></script>

    <style type="text/css">
        .get-in-touch {
            max-width: 800px;
            margin: 50px auto;
            background-color: #f9f9f9;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0px 0px 20px rgba(0, 0, 0, 0.1);
        }

        .get-in-touch .title {
            text-align: center;
            text-transform: uppercase;
            letter-spacing: 3px;
            font-size: 2.5em;
            padding-bottom: 30px;
            color: #000;
        }

        .contact-form .form-field {
            position: relative;
            margin: 24px 0;
        }

        .contact-form .input-text {
            display: block;
            width: 100%;
            height: 40px;
            padding: 10px;
            font-size: 13px;
            border: 1px solid #ddd;
            border-radius: 5px;
            background-color: #fff;
            transition: all 0.3s ease;
        }

        .contact-form .input-text:focus {
            border-color: #5543ca;
            box-shadow: 0 0 5px rgba(85, 67, 202, 0.2);
            outline: none;
        }

        .contact-form .label {
            position: absolute;
            top: -20px;
            left: 10px;
            font-size: 14px;
            font-weight: 600;
            background-color: #f9f9f9;
            padding: 0 5px;
            color: #555;
        }

        .contact-form .submit-btn {
            display: inline-block;
            background-color: #000;
            color: #fff;
            text-transform: uppercase;
            letter-spacing: 2px;
            font-size: 16px;
            padding: 12px 20px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            transition: background-color 0.3s ease;
        }

        .contact-form .submit-btn:hover {
            background-color: #444;
        }

        .account-text {
            text-align: center;
            margin-top: 20px;
            font-size: 15px;
            color: #000;
        }

        .account-text a {
            color: #5543ca;
            text-decoration: none;
            font-weight: bold;
        }

        .account-text a:hover {
            text-decoration: underline;
        }

        @media (max-width: 768px) {
            .get-in-touch {
                padding: 20px;
            }

            .get-in-touch .title {
                font-size: 2em;
            }
        }
    </style>
</head>

<body>
    <section class="get-in-touch">
        <h6 class="title">Enter your asset information</h6>
        <form class="contact-form row" method="POST" action="signup2.php">
            <!-- Assuming user_id is passed as a hidden field -->
            <input type="hidden" name="user_id" value="1"> <!-- Replace 1 with dynamic user_id -->

            <!-- <div class="form-field col-lg-6">
         <input id="yearly_income" name="yearly_income" class="input-text" type="number" step="0.01" placeholder="Enter yearly income or leave blank for 0">
         <label class="label" for="yearly_income">Yearly Income</label>
      </div> -->

            <div class="form-field col-lg-6">
                <select id="land_type" name="land_type" class="input-text">
                    <option value="">Select land type</option>
                    <option value="Agricultural">Agricultural</option>
                    <option value="Commercial">Commercial</option>
                    <option value="Residential">Residential</option>
                    <option value="N/A">N/A</option> <!-- Option for N/A -->
                </select>
                <label class="label" for="land_type">Land Type</label>
            </div>

            <div class="form-field col-lg-6">
                <input id="land_amount" name="land_amount" class="input-text" type="number" step="0.01" placeholder="Enter land amount or leave blank for 0">
                <label class="label" for="land_amount">Land Amount (in acres or square meters)</label>
            </div>

            <div class="form-field col-lg-6">
                <select id="vehicle_type" name="vehicle_type" class="input-text">
                    <option value="">Select vehicle type</option>
                    <option value="Car">Car</option>
                    <option value="Motorcycle">Motorcycle</option>
                    <option value="Truck">Truck</option>
                    <option value="N/A">N/A</option> <!-- Option for N/A -->
                </select>
                <label class="label" for="vehicle_type">Vehicle Type</label>
            </div>

            <!-- Dropdown for Vehicle Model -->
            <div class="form-field col-lg-6">
                <select id="vehicle_model" name="vehicle_model" class="input-text">
                    <option value="">Select vehicle model</option>
                    <option value="Toyota">Toyota</option>
                    <option value="Honda">Honda</option>
                    <option value="BMW">BMW</option>
                    <option value="N/A">N/A</option> <!-- Option for N/A -->
                </select>
                <label class="label" for="vehicle_model">Vehicle Model</label>
            </div>

            <!-- Dropdown for Business Asset -->
            <div class="form-field col-lg-6">
                <select id="business_asset" name="business_asset" class="input-text">
                    <option value="">Select business asset</option>
                    <option value="Shop">Shop</option>
                    <option value="Company">Company</option>
                    <option value="Factory">Factory</option>
                    <option value="N/A">N/A</option> <!-- Option for N/A -->
                </select>
                <label class="label" for="business_asset">Business Asset</label>
            </div>
            <div class="form-field col-lg-6">
                <select id="business_type" name="business_type" class="input-text">
                    <option value="">Select business asset</option>
                    <option value="privately Owned">privately Owned</option>
                    <option value="publicly owned">publicly owned</option>
                    <option value="N/A">N/A</option> <!-- Option for N/A -->
                </select>
                <label class="label" for="business_type">Business type</label>
            </div>

            <div class="form-field col-lg-12">
                <button class="submit-btn" type="submit">Submit</button>
            </div>
        </form>
    </section>


</body>

</html>