<?php
// Include your database connection file (assuming it's db.php)
session_start();
include('connect.php');
$user_id = $_SESSION['user_id'];

// Check if form is submitted
if ($_SERVER["REQUEST_METHOD"] == "POST") {
    // Collect asset data from the form
    // $user_id = $_SESSION['user_id']; // Assuming this comes from a session or is passed dynamically
    $company_name = $_POST['company_name'];
    $yearly_revenue = $_POST['yearly_revenue'];
    $cost = $_POST['cost'];
    $account_num = $_POST['account_num'];
    $tax_id = $_POST['tax_id'];
    $type = $_POST['type'];
    $contact = $_POST['contact'];
    $email = $_POST['email'];
    $date = $_POST['date'];

   
    $query = "INSERT INTO business (user_id,company_name, yearly_revenue, cost, account_num, tax_id,type,contact,email,date)
              VALUES (?,?,?,?,?,?,?,?,?,?)";

    $stmt = $conn->prepare($query);
    $stmt->bind_param("isddiissss",$user_id, $company_name, $yearly_revenue, $cost, $account_num, $tax_id,$type,$contact,$email,$date);

    if ($stmt->execute()) {
            header('location:dashboard2.php');
            exit();    

    $stmt->close();
    $conn->close();
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
   <h6 class="title">Register for your business!</h6>
   <form class="contact-form row" method="POST">
    <div class="form-field col-lg-6">
       <input id="company_name" name="company_name" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $name;}?>"  type="text" required>
       <label class="label" for="company_name">Company Name</label>
    </div>

  
    <div class="form-field half-width">
         <input id="user_id" name="user_id" class="input-text js-input" type="number" value="<?php echo $user_id; ?>" readonly>
         <label class="label" for="user_id">User ID</label>
      </div>

    <div class="form-field col-lg-6">
       <input id="yearly_revenue" name="yearly_revenue" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $yearly_revenue;}?>" type="number" required>
       <label class="label" for="yearly_revenue">Yearly revenue</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="cost" name="cost" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $cost;}?>" type="number" required>
       <label class="label" for="cost">Cost</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="account_num" name="account_num" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $account_num;}?>" type="text" required>
       <label class="label" for="account_num">Account Number(bank)</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="tax_id" name="tax_id" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $tax_id;}?>"  type="text" required>
       <label class="label" for="tax_id">Tax Identification Number</label>
    </div>

    <div class="form-field col-lg-6">
                <select id="type" name="type" class="input-text">
                    <option value="">Select business asset</option>
                    <option value="privately Owned">privately Owned</option>
                    <option value="publicly owned">publicly owned</option>
                    <option value="N/A">N/A</option> <!-- Option for N/A -->
                </select>
                <label class="label" for="type">Business type</label>
            </div>

    <div class="form-field col-lg-6">
       <input id="contact" name="contact" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $contact;}?>" type="number" required>
       <label class="label" for="contact">Contact Number</label>
    </div>

    <div class="form-field col-lg-6">
       <input id="email" name="email" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $email;}?>" type="email" required>
       <label class="label" for="email">Email</label>
    </div>

    <!-- <div class="form-field col-lg-6">
       <input id="password" name="password" class="input-text" type="password" required>
       <label class="label" for="password">Password</label>
    </div> -->
<!-- 
    <div class="form-field col-lg-6">
       <input id="again_password" name="again_password" class="input-text" type="password" required>
       <label class="label" for="again_password">Again Enter Your Password</label>
    </div> -->

    <div class="form-field col-lg-6">
       <input id="date" name="date" class="input-text" value ="<?php if (isset($_POST['submit'])){echo $date;}?>" type="date" required>
       <label class="label" for="date">Registration Date</label>
    </div>

    <div class="form-field col-lg-12">
       <button class="submit-btn" type="submit" name="submit">Register</button>
    </div>

    <!-- Already Have an Account Text -->
    <div class="account-text col-lg-12">
      Already registered? <a href="businessdashboard.php">Business</a>
    </div>
  </form>
</section>