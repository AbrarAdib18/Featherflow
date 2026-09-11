<?php
include('connect.php'); 
session_start();

if (!isset($_SESSION['user_id'])) {
    header("Location: login.php");
    exit();
}

$user_id = $_SESSION['user_id'];

$query = "SELECT first_name, last_name, email, nid, phone FROM registered WHERE user_id = '$user_id'";
$result = mysqli_query($conn, $query);

if ($result && mysqli_num_rows($result) > 0) {
    $user_data = mysqli_fetch_assoc($result);
} else {
    echo "<script>alert('User data not found.');</script>";
}

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $first_name = $_POST['first_name'];
    $last_name = $_POST['last_name'];
    $email = $_POST['email'];
    $nid =  $_POST['nid'];
    $contact_number =  $_POST['contact_number'];
    $tax_category_id =  $_POST['tax_category_id'];
    $paying_gateway =  $_POST['paying_gateway'];
    $paying_amount = $_POST['paying_amount'];
    $paying_date =  $_POST['paying_date'];

    $query = "INSERT INTO payment_incometax 
              (user_id, paying_amount, paying_date, paying_gateway, first_name, last_name, email, nid, contact_number, tax_category_id) 
              VALUES 
              ('$user_id', '$paying_amount', '$paying_date', '$paying_gateway', '$first_name', '$last_name', '$email', '$nid', '$contact_number', '$tax_category_id')";

    if (mysqli_query($conn, $query)) {
        echo "<script>alert('Payment successful!');</script>";
        header("Location: pay.php");
    } else {
        echo "<script>alert('Error: " . mysqli_error($conn) . "');</script>";
    }
}
?>

<style type="text/css">
/* General Styling */
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
  background-color: #333;
}

/* Back to Home Button */
.back-button {
    position: absolute;
    top: 20px;
    right: 20px;
    background-color: black;
    color: white;
    padding: 10px 20px;
    border-radius: 8px;
    text-decoration: none;
    font-size: 16px;
    transition: background-color 0.3s ease-in-out;
}

.back-button:hover {
    background-color: #333;
}

/* Responsive Design */
@media (max-width: 768px) {
  .form-field.half-width {
    width: 100%;
  }
}
</style>

<link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet">

<!-- Back to Home Button -->
<a href="dashboard2.php" class="back-button">Back to Home</a>

<!-- Payment Form -->
<section class="get-in-touch">
   <h1 class="title">Pay Your Income Tax</h1>
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
         <input id="nid" name="nid" class="input-text js-input" value="<?php echo isset($user_data['nid']) ? $user_data['nid'] : ''; ?>" type="number" min="1" readonly>
         <label class="label" for="nid">NID</label>
      </div>

      <div class="form-field half-width">
         <input id="contact_number" name="contact_number" class="input-text js-input" value="<?php echo isset($user_data['phone']) ? $user_data['phone'] : ''; ?>" type="number" min="1" readonly>
         <label class="label" for="contact_number">Contact Number</label>
      </div>

      <div class="form-field">
         <input id="tax_category_id" name="tax_category_id" class="input-text js-input" type="number" min="1" required>
         <label class="label" for="tax_category_id">Tax Category ID</label>
      </div>

      <div class="form-field half-width">
         <input id="paying_gateway" name="paying_gateway" class="input-text js-input" type="text" required>
         <label class="label" for="paying_gateway">Paying Gateway</label>
      </div>

      <div class="form-field">
         <input id="paying_amount" name="paying_amount" class="input-text js-input" type="number" min="1" required>
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
