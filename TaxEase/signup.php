<?php
session_start();
include("connect.php");

if (isset($_POST['submit'])) {
    $first_name = $_POST["first_name"];
    $last_name = $_POST["last_name"];
    $nid = $_POST["nid"];
    $etin = $_POST["etin"];
    $address = $_POST["address"];
    $gender = $_POST["gender"];
    $registration_date = $_POST["registration_date"];
    $incomestatus = $_POST["incomestatus"];
    $password = $_POST["password"];
    $again_password = $_POST["again_password"];
    $phone = $_POST["phone"];
    $email = $_POST["email"];

    // Check if any required field is empty
    if (!empty($first_name) && !empty($last_name) && !empty($nid) && !empty($etin) && !empty($address) && !empty($gender) && !empty($registration_date) && !empty($incomestatus) && !empty($password) && !empty($again_password) && !empty($phone) && !empty($email)) {
        if ($password === $again_password) {
            $existing_fields = [];

            // Check for existing account fields
            if ($conn->query("SELECT * FROM registered WHERE nid='$nid'")->num_rows > 0) {
                $existing_fields[] = 'NID';
            }
            if ($conn->query("SELECT * FROM registered WHERE etin='$etin'")->num_rows > 0) {
                $existing_fields[] = 'E-TIN';
            }
            if ($conn->query("SELECT * FROM registered WHERE email='$email'")->num_rows > 0) {
                $existing_fields[] = 'Email';
            }

            if (!empty($existing_fields)) {
                echo 'Account already exists for the following fields: ' . implode(', ', $existing_fields) . '. Please use different values.';
            } else {
                // No existing account, proceed to insert
                $sql = "INSERT INTO registered (first_name, last_name, nid, etin, address, gender, registration_date, incomestatus, password, phone, email) VALUES ('$first_name', '$last_name', '$nid', '$etin', '$address', '$gender', '$registration_date', '$incomestatus', '$password', '$phone', '$email')";

                if ($conn->query($sql) === TRUE) {
                  $user_id = $conn->insert_id;

                 // Step 3: Store the user_id in the session to use it in the next step (asset insertion)
                 $_SESSION['user_id'] = $user_id;

                    header('location:signup2.php');
                    exit();
                } else {
                    echo "Error: " . $sql . "<br>" . $conn->error;
                }
            }
        } else {
            echo 'Passwords do not match.';
        }
    }
}
?>

 
<link href="//maxcdn.bootstrapcdn.com/bootstrap/4.1.1/css/bootstrap.min.css" rel="stylesheet" id="bootstrap-css">
<script src="//maxcdn.bootstrapcdn.com/bootstrap/4.1.1/js/bootstrap.min.js"></script>
<script src="//cdnjs.cloudflare.com/ajax/libs/jquery/3.2.1/jquery.min.js"></script>

<style type="text/css">
/* Main container styling */
.get-in-touch {
  max-width: 800px;
  margin: 50px auto;
  background-color: #f9f9f9;
  padding: 40px;
  border-radius: 10px;
  box-shadow: 0px 0px 20px rgba(0, 0, 0, 0.1);
}

/* Form Title - Full Black */
.get-in-touch .title {
  text-align: center;
  text-transform: uppercase;
  letter-spacing: 3px;
  font-size: 2.5em;
  padding-bottom: 30px;
  color: #000; /* Changed to full black */
}

/* Form Field Styling */
.contact-form .form-field {
  position: relative;
  margin: 24px 0;
}

.contact-form .input-text {
  display: block;
  width: 100%;
  height: 40px;
  padding: 10px;
  font-size: 16px;
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

/* Submit Button - Black */
.contact-form .submit-btn {
  display: inline-block;
  background-color: #000; /* Button is now black */
  color: #fff; /* White text for contrast */
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
  background-color: #444; /* Slightly lighter black on hover */
}

/* 'Already have an account?' Text */
.contact-form .account-text {
  text-align: center;
  margin-top: 20px;
  font-size: 16px;
  color: #000; /* Text in black */
}

.contact-form .account-text a {
  color: #5543ca; /* Link color */
  text-decoration: none;
  font-weight: bold;
}

.contact-form .account-text a:hover {
  text-decoration: underline;
}

/* Responsive adjustments */
@media (max-width: 768px) {
  .get-in-touch {
    padding: 20px;
  }

  .get-in-touch .title {
    font-size: 2em;
  }
}
</style>

<!-- Registration Form Section -->
<section class="get-in-touch">
   <h6 class="title">Register to Pay Your Taxes!</h6>
   <form class="contact-form row" method="POST">
    <div class="form-field col-lg-6">
       <input id="first_name" name="first_name" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $first_name;}?>"  type="text" required>
       <label class="label" for="first_name">First Name</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="last_name" name="last_name" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $last_name;}?>" type="text" required>
       <label class="label" for="last_name">Last Name</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="nid" name="nid" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $nid;}?>" type="number" required>
       <label class="label" for="nid">NID Number</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="etin" name="etin" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $etin;}?>" type="number" required>
       <label class="label" for="etin">E-TIN Number</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="address" name="address" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $address;}?>" type="text" required>
       <label class="label" for="address">Address</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="gender" name="gender" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $gender;}?>"  type="text" required>
       <label class="label" for="gender">Gender</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="incomestatus" name="incomestatus" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $incomestatus;}?>" type="number" required>
       <label class="label" for="incomestatus">Yearly Income</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="phone" name="phone" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $phone;}?>" type="number" required>
       <label class="label" for="phone">Contact Number</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="email" name="email" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $email;}?>" type="email" required>
       <label class="label" for="email">Email</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="password" name="password" class="input-text" type="password" required>
       <label class="label" for="password">Password</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="again_password" name="again_password" class="input-text" type="password" required>
       <label class="label" for="again_password">Again Enter Your Password</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="registration_date" name="registration_date" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $registration_date;}?>" type="date" required>
       <label class="label" for="registration_date">Registration Date</label>
    </div>

    <div class="form-field col-lg-12">
       <button class="submit-btn" type="submit" name="submit">Next</button>
    </div>

    <!-- Already Have an Account Text -->
    <div class="account-text col-lg-12">
      Already have an account? <a href="login.php">Login</a>
    </div>
  </form>
</section>
