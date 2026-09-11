<?php
include('connect.php'); 
session_start();

// Check if user is logged in
if (!isset($_SESSION['user_id'])) {
    header("Location: login.php");
    exit();
}

// Get the user ID from the session
$user_id = $_SESSION['user_id'];

// Fetch user details from the database
$query = "SELECT first_name, last_name, email, phone FROM registered WHERE user_id = '$user_id'";
$result = mysqli_query($conn, $query);

if ($result && mysqli_num_rows($result) > 0) {
    $user_data = mysqli_fetch_assoc($result);
} else {
    echo "<script>alert('User data not found.');</script>";
}

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    // Collect form data
    $first_name = $_POST['first_name'];
    $last_name = $_POST['last_name'];
    $email = $_POST['email'];
    $contact_number = $_POST['contact_number'];
    $zone = $_POST['zone'];
    $vehicle_type = $_POST['vehicle_type'];
    $vehicle_model = $_POST['vehicle_model'];
    $vehicle_regi_number = $_POST['vehicle_regi_number'];
    $paying_gateway = $_POST['paying_gateway'];
    $paying_amount = $_POST['paying_amount'];
    $paying_date = $_POST['paying_date'];

    // Insert data into the payment_vehicle table
    $query = "INSERT INTO payment_vehicle 
              (user_id, paying_amount, paying_date, paying_gateway, first_name, last_name, email, contact_number, zone, vehicle_type, vehicle_model, vehicle_regi_number) 
              VALUES 
              ('$user_id', '$paying_amount', '$paying_date', '$paying_gateway', '$first_name', '$last_name', '$email', '$contact_number', '$zone', '$vehicle_type', '$vehicle_model', '$vehicle_regi_number')";

    if (mysqli_query($conn, $query)) {
        echo "<script>alert('Payment successful!');</script>";
        header("Location: pay.php");
    } else {
        echo "<script>alert('Error: " . mysqli_error($conn) . "');</script>";
    }
}
?>

<!-- CSS for the Vehicle Tax Payment Form -->
<style type="text/css">
body {
  font-family: 'Roboto', sans-serif;
  background-color: #f4f7f6;
  margin: 0;
  padding: 0;
}

.get-in-touch {
  max-width: 900px;
  margin: 60px auto;
  background: #fff;
  border-radius: 12px;
  box-shadow: 0 5px 15px rgba(0, 0, 0, 0.1);
  padding: 30px;
}

.title {
  text-align: center;
  font-size: 2.5rem;
  letter-spacing: 1px;
  margin-bottom: 40px;
  color: #333;
}

.contact-form {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
}

.form-field {
  position: relative;
  margin: 20px 0;
  width: 100%;
}

.form-field.half-width {
  width: 48%;
}

.input-text {
  width: 100%;
  padding: 15px;
  border: 2px solid #e0e0e0;
  border-radius: 8px;
  font-size: 16px;
  color: #333;
  background-color: #fafafa;
  transition: all 0.3s ease-in-out;
}

.input-text:focus {
  border-color: #007bff;
  background-color: #fff;
  outline: none;
}

.label {
  position: absolute;
  top: -18px;
  left: 20px;
  background: #fff;
  font-size: 14px;
  color: #333;
  padding: 0 5px;
}

.submit-btn {
  background-color: black;
  color: white;
  padding: 12px 20px;
  font-size: 16px;
  letter-spacing: 1px;
  border: none;
  border-radius: 8px;
  cursor: pointer;
  margin-top: 20px;
  width: 100%;
  transition: background-color 0.3s ease-in-out;
}

.submit-btn:hover {
  background-color: #444;
}

/* Back to Home Button */
.back-home-btn {
  position: absolute;
  top: 20px;
  right: 20px;
  background-color: black;
  color: white;
  padding: 10px 15px;
  font-size: 16px;
  border: none;
  border-radius: 5px;
  cursor: pointer;
  text-decoration: none;
}

.back-home-btn:hover {
  background-color: #444;
}

/* Responsive Design */
@media (max-width: 768px) {
  .form-field.half-width {
    width: 100%;
  }
}
</style>

<link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">

<!-- Payment Form -->
<section class="get-in-touch">
   <a href="dashboard2.php" class="back-home-btn">Back to Home</a>
   <h1 class="title">Pay Your Vehicle Tax</h1>
   <form class="contact-form row" method="POST">
      <div class="form-field half-width">
         <input id="first_name" name="first_name" class="input-text js-input" value="<?php echo isset($user_data['first_name']) ? $user_data['first_name'] : ''; ?>" type="text" readonly>
         <label class="label" for="first_name">First Name</label>
      </div>

      <div class="form-field half-width">
         <input id="last_name" name="last_name" class="input-text js-input" value="<?php echo isset($user_data['last_name']) ? $user_data['last_name'] : ''; ?>" type="text" readonly>
         <label class="label" for="last_name">Last Name</label>
      </div>

      <div class="form-field half-width">
         <input id="email" name="email" class="input-text js-input" value="<?php echo isset($user_data['email']) ? $user_data['email'] : ''; ?>" type="email" readonly>
         <label class="label" for="email">Email</label>
      </div>
      <div class="form-field half-width">
         <input id="user_id" name="user_id" class="input-text js-input" type="number" value="<?php echo $user_id; ?>" readonly>
         <label class="label" for="user_id">User ID</label>
      </div>
      <div class="form-field half-width">
         <input id="contact_number" name="contact_number" class="input-text js-input" value="<?php echo isset($user_data['phone']) ? $user_data['phone'] : ''; ?>" type="number" readonly>
         <label class="label" for="contact_number">Contact Number</label>
      </div>

      <div class="form-field half-width">
         <input id="zone" name="zone" class="input-text js-input" type="text" required>
         <label class="label" for="zone">Zone</label>
      </div>

      <div class="form-field half-width">
         <input id="vehicle_type" name="vehicle_type" class="input-text js-input" type="text" required>
         <label class="label" for="vehicle_type">Vehicle Type</label>
      </div>

      <div class="form-field half-width">
         <input id="vehicle_model" name="vehicle_model" class="input-text js-input" type="text" required>
         <label class="label" for="vehicle_model">Vehicle Model</label>
      </div>

      <div class="form-field half-width">
         <input id="vehicle_regi_number" name="vehicle_regi_number" class="input-text js-input" type="number" required>
         <label class="label" for="vehicle_regi_number">Vehicle Registration Number</label>
      </div>

      <div class="form-field half-width">
         <input id="paying_gateway" name="paying_gateway" class="input-text js-input" type="text" required>
         <label class="label" for="paying_gateway">Paying Gateway</label>
      </div>

      <div class="form-field half-width">
         <input id="paying_amount" name="paying_amount" class="input-text js-input" type="number" required>
         <label class="label" for="paying_amount">Paying Amount</label>
      </div>

      <div class="form-field half-width">
         <input id="paying_date" name="paying_date" class="input-text js-input" type="date" required>
         <label class="label" for="paying_date">Paying Date</label>
      </div>

      <div class="form-field">
         <button class="submit-btn" type="submit" name="submit">Submit</button>
      </div>
   </form>
</section>
