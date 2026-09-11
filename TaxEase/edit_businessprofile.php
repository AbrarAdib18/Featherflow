<?php
// Start session to check if the user is logged in
session_start();
$conn = new PDO("mysql:host=localhost;dbname=tax", "root", "");
if ($conn == false) {
    die("Connection failed");
}

// Check if user is logged in
if (!isset($_SESSION['user_id'])) {
    header("Location: login.php");
    exit();
}

// Fetch the user's profile data from the database
$user_id = $_SESSION['user_id'];
$sql = "SELECT company_name, yearly_revenue, cost, contact, email FROM business WHERE user_id = ?";
$statement = $conn->prepare($sql);
$statement->execute([$user_id]);
$user_data = $statement->fetch(PDO::FETCH_ASSOC);

if (!$user_data) {
    die("User not found.");
}

// Check if the form is submitted
if (isset($_POST['submit'])) {
    $company_name = $_POST['company_name'];
    $yearly_revenue = $_POST['yearly_revenue'];
    $cost = $_POST['cost'];
    $contact = $_POST['contact'];
    $email = $_POST['email'];

    // Update name, contact, and cost
    $sql = "UPDATE business SET company_name = ?, yearly_revenue = ?, cost = ?, contact = ?, email = ? WHERE user_id = ?";
    $statement = $conn->prepare($sql);
    $statement->execute([$company_name, $yearly_revenue, $cost, $contact, $email, $user_id]); // Added $user_id to the array

    // Redirect to profile page or a success page
    header("Location: businessdashboard.php");
    exit();
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Edit Profile</title>
    <link rel="stylesheet" type="text/css" href="css/bootstrap.css" />
</head>
<body>
    <div class="container" style="margin-top: 50px; margin-bottom: 50px;">
        <div class="row">
            <div class="offset-md-3 col-md-6">
                <h1 class="text-center">Edit Your Profile</h1>
                <form method="POST" action="edit_businessprofile.php">
                    <!-- First Name Field -->
                    <div class="form-group">
                        <label for="company_name">Company Name:</label>
                        <input type="text" name="company_name" class="form-control" value="<?php echo $user_data['company_name']; ?>" required />
                    </div>

                    <!-- Last Name Field -->
                    <div class="form-group">
                        <label for="yearly_revenue">Yearly Revenue:</label>
                        <input type="number" name="yearly_revenue" class="form-control" value="<?php echo $user_data['yearly_revenue']; ?>" required />
                    </div>

                    <!-- cost Field -->
                    <div class="form-group">
                        <label for="cost">cost:</label>
                        <input type="cost" name="cost" class="form-control" value="<?php echo $user_data['cost']; ?>" required />
                    </div>

                    <!-- contact Number Field -->
                    <div class="form-group">
                        <label for="contact">contact Number:</label>
                        <input type="number" name="contact" class="form-control" value="<?php echo $user_data['contact']; ?>" required />
                    </div>

                    <!-- email Field (Optional) -->
                    <div class="form-group">
                        <label for="email">New email (Leave blank if not changing):</label>
                        <input type="email" name="email" class="form-control" />
                    </div>

                    <!-- Submit Button -->
                    <input type="submit" name="submit" class="btn btn-warning" value="Update Profile" />
                </form>
            </div>
        </div>
    </div>
</body>
</html>
