<?php
// Start session to check if the user is logged in
session_start();
try {
    $conn = new PDO("mysql:host=localhost;dbname=tax", "root", "");
    $conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    die("Connection failed: " . $e->getMessage());
}

// Check if user is logged in
if (!isset($_SESSION['user_id'])) {
    header("Location: login.php");
    exit();
}

// Fetch the user's profile data from the database
$user_id = $_SESSION['user_id'];
$sql = "SELECT first_name, last_name, phone, email FROM registered WHERE user_id = ?";
$statement = $conn->prepare($sql);
$statement->execute([$user_id]);
$user_data = $statement->fetch(PDO::FETCH_ASSOC);

if (!$user_data) {
    die("User not found.");
}

// Check if the form is submitted
if (isset($_POST['submit'])) {
    $first_name = trim($_POST['first_name']);
    $last_name = trim($_POST['last_name']);
    $email = trim($_POST['email']);
    $phone = trim($_POST['phone']);
    $password = $_POST['password'];

    // Basic server-side validation (you can expand this as needed)
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $error_message = "Invalid email format!";
    } else {
        try {
            if (!empty($password)) {
                // Hash the new password
                $hashed_password = password_hash($password, PASSWORD_DEFAULT);

                // Update name, phone, email, and password
                $sql = "UPDATE registered SET first_name = ?, last_name = ?, phone = ?, email = ?, password = ? WHERE user_id = ?";
                $statement = $conn->prepare($sql);
                $statement->execute([$first_name, $last_name, $phone, $email, $hashed_password, $user_id]);
            } else {
                // Only update name, phone, and email
                $sql = "UPDATE registered SET first_name = ?, last_name = ?, phone = ?, email = ? WHERE user_id = ?";
                $statement = $conn->prepare($sql);
                $statement->execute([$first_name, $last_name, $phone, $email, $user_id]);
            }

            // Redirect to profile page or a success page
            header("Location: dashboard2.php");
            exit();
        } catch (PDOException $e) {
            $error_message = "Error updating profile: " . $e->getMessage();
        }
    }
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Edit Profile - TaxEase</title>
    <!-- Google Fonts -->
    <link href="https://fonts.googleapis.com/css?family=Open+Sans:300,400,600,700" rel="stylesheet" />
    <!-- Bootstrap CSS -->
    <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.0/css/bootstrap.min.css">
    <style>
        /* Global Styles */
        body {
            background-color: #ffffff; /* White background */
            color: #000000; /* Black text */
            font-family: 'Open Sans', sans-serif;
            margin: 0;
            padding: 0;
            height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        /* Card Container */
        .edit-profile-card {
            background-color: #f9f9f9; /* Light background for the card */
            border-radius: 15px;
            box-shadow: 0 8px 25px rgba(0, 0, 0, 0.1);
            padding: 40px;
            max-width: 500px;
            width: 100%;
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }

        .edit-profile-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 12px 30px rgba(0, 0, 0, 0.2);
        }

        /* Heading */
        .edit-profile-card h1 {
            text-align: center;
            margin-bottom: 30px;
            font-size: 28px;
            color: #000000; /* Black color */
            font-weight: 700;
        }

        /* Form Groups */
        .form-group label {
            color: #000000; /* Black labels */
            font-weight: 600;
            margin-bottom: 8px;
            display: block;
        }

        .form-control {
            background-color: #ffffff; /* White background for inputs */
            border: 1px solid #ced4da;
            border-radius: 5px;
            padding: 12px 15px;
            color: #000000; /* Black text */
            font-size: 14px;
            transition: border-color 0.3s ease, box-shadow 0.3s ease;
        }

        .form-control:focus {
            border-color: #000000; /* Black border on focus */
            box-shadow: 0 0 5px rgba(0, 0, 0, 0.1);
            outline: none;
        }

        /* Submit Button */
        .btn-submit {
            width: 100%;
            background-color: #000000; /* Black background */
            color: #ffffff; /* White text */
            padding: 12px;
            border: none;
            border-radius: 5px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
            transition: background-color 0.3s ease, transform 0.2s ease;
        }

        .btn-submit:hover {
            background-color: #333333; /* Darker black on hover */
            transform: translateY(-2px);
        }

        /* Error Message */
        .error-message {
            background-color: #ff4d4d; /* Red background */
            color: #ffffff; /* White text */
            padding: 10px 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            text-align: center;
            font-weight: 600;
        }

        /* Success Message */
        .success-message {
            background-color: #28a745; /* Green background */
            color: #ffffff; /* White text */
            padding: 10px 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            text-align: center;
            font-weight: 600;
        }

        /* Responsive Adjustments */
        @media (max-width: 576px) {
            .edit-profile-card {
                padding: 30px 20px;
            }

            .edit-profile-card h1 {
                font-size: 24px;
            }

            .btn-submit {
                padding: 10px;
                font-size: 14px;
            }
        }
    </style>
</head>
<body>
    <div class="edit-profile-card">
        <h1>Edit Your Profile</h1>
        <?php if (isset($error_message)): ?>
            <div class="error-message">
                <?php echo htmlspecialchars($error_message); ?>
            </div>
        <?php endif; ?>
        <?php if (isset($_GET['success'])): ?>
            <div class="success-message">
                Profile updated successfully!
            </div>
        <?php endif; ?>
        <form method="POST" action="editprofile.php">
            <!-- First Name Field -->
            <div class="form-group">
                <label for="first_name">First Name:</label>
                <input type="text" name="first_name" class="form-control" value="<?php echo htmlspecialchars($user_data['first_name']); ?>" required />
            </div>

            <!-- Last Name Field -->
            <div class="form-group">
                <label for="last_name">Last Name:</label>
                <input type="text" name="last_name" class="form-control" value="<?php echo htmlspecialchars($user_data['last_name']); ?>" required />
            </div>

            <!-- Email Field -->
            <div class="form-group">
                <label for="email">Email:</label>
                <input type="email" name="email" class="form-control" value="<?php echo htmlspecialchars($user_data['email']); ?>" required />
            </div>

            <!-- Phone Number Field -->
            <div class="form-group">
                <label for="phone">Phone Number:</label>
                <input type="text" name="phone" class="form-control" value="<?php echo htmlspecialchars($user_data['phone']); ?>" required />
            </div>

            <!-- Password Field (Optional) -->
            <div class="form-group">
                <label for="password">New Password (Leave blank if not changing):</label>
                <input type="password" name="password" class="form-control" />
            </div>

            <!-- Submit Button -->
            <input type="submit" name="submit" class="btn-submit" value="Update Profile" />
        </form>
    </div>

    <!-- Bootstrap JS and dependencies (Optional for additional interactivity) -->
    <script src="https://code.jquery.com/jquery-3.5.1.slim.min.js" integrity="sha384-DfXdOtmVgAwfGJN1/vVQx7Zplm21GgI1XdtIiq1iIfdN7ZpkaZy/xxO9uJp9IGW4" crossorigin="anonymous"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@4.5.0/dist/js/bootstrap.bundle.min.js" integrity="sha384-1CmrxMRARb6aLqgBO7yyAxTOQE2AKb9GfXnE5C2VJ2M1dfGvJoG7iQVplKdfwF8N" crossorigin="anonymous"></script>
</body>
</html>
