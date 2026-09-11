<?php
session_start();
include("connect.php");

// Check if the user is logged in
if (!isset($_SESSION['user_id'])) {
    // Redirect to login if not logged in
    header("Location: login.php");
    exit();
}
$username = isset($_SESSION['first_name']) ? $_SESSION['first_name'] : 'Guest';

$is_admin = isset($_SESSION['is_admin']) && $_SESSION['is_admin'] == 1;

$query1 = "SELECT user_id, first_name, last_name, nid, total_paid FROM registered WHERE is_admin = 0";
$result = $conn->query($query1);

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    // Get user_id from the POST request
    if (isset($_POST['user_id'])) {
        $user_id = $_POST['user_id'];

        // Query to get the first and last name of the selected user
        $query2 = "SELECT first_name, last_name FROM registered WHERE user_id = ?";
        $stmt = $conn->prepare($query2);
        $stmt->bind_param("i", $user_id);
        $stmt->execute();
        $result2 = $stmt->get_result();

        if ($result2->num_rows > 0) {
            $row = $result2->fetch_assoc();
            $first_name = $row['first_name'];
            $last_name = $row['last_name'];

            // Concatenate first_name and last_name
            $full_name = $first_name . ' ' . $last_name;

            // Check if the user already exists in the 'observe' table
            $query_check = "SELECT * FROM observe WHERE user_id = ?";
            $stmt_check = $conn->prepare($query_check);
            $stmt_check->bind_param("i", $user_id);
            $stmt_check->execute();
            $result_check = $stmt_check->get_result();

            if ($result_check->num_rows > 0) {
                // User already exists in the 'observe' table
                echo "<script>alert('User is already being observed!');</script>";
            } else {
                // Insert into the 'observe' table if not already present
                $query3 = "INSERT INTO observe (user_id, name) VALUES (?, ?)";
                $stmt3 = $conn->prepare($query3);
                $stmt3->bind_param("is", $user_id, $full_name);

                if ($stmt3->execute()) {
                    echo "<script>alert('User added to observe table!');</script>";
                    //header("Location: security.php");
                } else {
                    echo "Error observing user.";
                }
            }
        } else {
            echo "User not found.";
        }
    }
}
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Audit Needed</title>
    <link href="https://fonts.googleapis.com/css?family=Open+Sans:300,400,600,700" rel="stylesheet" />
    <style>
        /* Global Font Color */
        body, h1, th, td, a, button {
            color: #ffffff; /* White color for all text */
        }

        /* Navbar styling */
        .navbar {
            background-color: #2a2a2a; /* Darker background for better contrast */
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.5);
            padding: 15px 20px; /* More padding for better spacing */
        }
        .navbar .container {
            display: flex;
            justify-content: space-between; /* Space between brand and nav links */
            align-items: center;
            position: relative;
        }
        .navbar .navbar-brand {
            font-size: 2.5em; /* Increased font size */
            font-weight: bold;
            color: #ffffff; /* White color */
            letter-spacing: 2px;
        }
        .navbar .nav-item .nav-link {
            text-transform: uppercase;
            padding: 10px 15px;
            font-size: 1em; /* Slightly larger font size */
            font-weight: bold;
            color: #ffffff; /* White color for nav links */
            margin: 0 10px; /* Space between links */
            transition: all 0.3s ease;
            position: relative; /* For pseudo-element positioning */
        }
        .navbar .nav-item .nav-link:hover {
            color: #f0a500; /* Change text color on hover */
        }
        .navbar .nav-item .nav-link::after {
            content: "";
            display: block;
            width: 0;
            height: 2px;
            background: #f0a500; /* Gold underline */
            transition: width 0.3s;
            position: absolute;
            bottom: -5px;
            left: 0;
        }
        .navbar .nav-item .nav-link:hover::after {
            width: 100%; /* Full underline on hover */
        }

        /* Body styling */
        body {
            font-family: 'Open Sans', sans-serif;
            background-color: #121212;
            margin: 0;
            padding: 20px;
        }
        h1 {
            text-align: center;
            margin-bottom: 20px;
            font-size: 2.5em; /* Increased header size */
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }
        th, td {
            padding: 15px;
            text-align: center;
            border: 1px solid #444; /* Dark border */
        }
        th {
            background-color: #1a1a1a;
            color: #ffffff; /* White header text */
        }
        tr:nth-child(even) {
            background-color: #2a2a2a; /* Slightly lighter row color */
        }
        tr:hover {
            background-color: #444; /* Highlight row on hover */
        }
        .button {
            background-color: #f0a500; /* Gold button */
            color: white;
            padding: 10px 20px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            transition: background-color 0.3s ease;
            font-weight: bold; /* Bold button text */
        }
        .button:hover {
            background-color: #e0a100; /* Darker gold on hover */
        }
    </style>
</head>
<body>
<nav class="navbar navbar-expand-md navbar-dark">
    <div class="container">
        <a class="navbar-brand" href="home.php"><b>TaxEase</b></a>
        <div class="nav-links">
            <ul class="navbar-nav d-flex flex-row">
                <li class="nav-item">
                    <a class="nav-link" href="home.php">Home</a>
                </li>
                <?php if ($is_admin == '1'): ?>
                    <!-- If user is admin, show options to edit, add, and delete FAQs -->
                    <li class="nav-item">
                        <a class="nav-link" href="add.php">Update FAQ</a>
                    </li>
                <?php endif; ?>
            </ul>
        </div>
    </div>
</nav>

<h1>Audit Required!</h1>

<table>
    <thead>
    <tr>
        <th>User ID</th>
        <th>Name</th>
        <th>NID</th>
        <th>Total Tax Paid (per year)</th>
        <th>Action</th>
    </tr>
    </thead>
    <tbody>
    <?php
    // Display user information and tax payment
    if ($result->num_rows > 0) {
        while ($row = $result->fetch_assoc()) {
            echo '<tr>';
            echo '<td>' . htmlspecialchars($row['user_id']) . '</td>';
            echo '<td>' . htmlspecialchars($row['first_name'] . ' ' . $row['last_name']) . '</td>';
            echo '<td>' . htmlspecialchars($row['nid']) . '</td>';
            echo '<td>' . htmlspecialchars($row['total_paid']) . '</td>';
            echo '<td>';
            echo '<form method="POST">';
            echo '<input type="hidden" name="user_id" value="' . htmlspecialchars($row['user_id']) . '">';
            echo '<button type="submit" name="submit" value="accepted" class="button">Observe</button>';
            echo '</form>';
            echo '</td>';
            echo '</tr>';
        }
    } else {
        echo '<tr><td colspan="5">No user data found.</td></tr>';
    }
    ?>
    </tbody>
</table>

</body>
</html>
