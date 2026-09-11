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

$sql = "SELECT 
            u.user_id AS u_id, 
            u.first_name, 
            u.last_name,
            'Income Tax' AS tax_category,
            pi.paying_date AS income_tax_paiddate,
            pl.paying_date AS land_tax_paiddate,
            pv.paying_date AS vehicle_tax_paiddate,
            CASE 
                WHEN pi.paying_date > '2024-04-15' THEN 'Late Income Tax Payment'
                WHEN pl.paying_date > '2024-06-30' THEN 'Late Land Tax Payment'
                WHEN pv.paying_date > '2024-08-15' THEN 'Late Vehicle Tax Payment'
                ELSE 'On Time'
            END AS payment_status
        FROM 
            registered u
        LEFT JOIN 
            payment_incometax pi ON u.user_id = pi.user_id
        LEFT JOIN 
            payment_land pl ON u.user_id = pl.user_id
        LEFT JOIN 
            payment_vehicle pv ON u.user_id = pv.user_id
        WHERE 
            (pi.paying_date > '2024-04-15' 
             OR pl.paying_date > '2024-06-30' 
             OR pv.paying_date > '2024-08-15')
        GROUP BY 
            u.user_id
        ORDER BY 
            payment_status DESC;";

$result = $conn->query($sql);

$conn->close();
?>


<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Audit Needed</title>
    <link href="https://fonts.googleapis.com/css?family=Open+Sans:300,400,600,700" rel="stylesheet" />
    <style>
        /* Reset some default styles */
        *, *::before, *::after {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        /* Global Font Color */
        body {
            font-family: 'Open Sans', sans-serif;
            background-color: #121212;
            color: #ffffff; /* White text */
            margin: 0;
            padding: 20px;
        }

        /* Navbar styling */
        .navbar {
            background-color: #1a1a1a;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.3);
            padding: 15px 0;
            position: sticky;
            top: 0;
            z-index: 1000;
        }

        .navbar .container {
            display: flex;
            justify-content: space-between;
            align-items: center;
            max-width: 1200px;
            margin: 0 auto;
            padding: 0 20px;
        }

        .navbar .navbar-brand {
            font-size: 2em; /* Larger font size */
            font-weight: 700;
            color: #ffffff;
            text-decoration: none;
            letter-spacing: 1px;
        }

        .navbar .nav-links {
            display: flex;
            align-items: center;
        }

        .navbar .nav-item {
            list-style: none;
        }

        .navbar .nav-link {
            text-transform: uppercase;
            padding: 10px 20px;
            font-size: 0.9em;
            font-weight: 600;
            color: #ffffff;
            text-decoration: none;
            border: 2px solid transparent;
            border-radius: 5px;
            transition: all 0.3s ease;
            margin-left: 10px; /* Space between links */
        }

        .navbar .nav-link:hover {
            background-color: #333333;
            border-color: #f0a500;
            color: #f0a500;
        }

        /* Responsive Toggler */
        .navbar-toggler {
            display: none; /* Hidden on large screens */
            background: none;
            border: none;
            cursor: pointer;
        }

        .navbar-toggler-icon {
            width: 25px;
            height: 3px;
            background-color: #ffffff;
            display: block;
            position: relative;
            transition: all 0.3s ease;
        }

        .navbar-toggler-icon::before,
        .navbar-toggler-icon::after {
            content: '';
            width: 25px;
            height: 3px;
            background-color: #ffffff;
            position: absolute;
            left: 0;
            transition: all 0.3s ease;
        }

        .navbar-toggler-icon::before {
            top: -8px;
        }

        .navbar-toggler-icon::after {
            top: 8px;
        }

        .navbar-toggler.active .navbar-toggler-icon {
            background-color: transparent;
        }

        .navbar-toggler.active .navbar-toggler-icon::before {
            transform: rotate(45deg) translate(5px, 5px);
        }

        .navbar-toggler.active .navbar-toggler-icon::after {
            transform: rotate(-45deg) translate(5px, -5px);
        }

        /* Body styling */
        h1 {
            text-align: center;
            margin-bottom: 30px;
            font-size: 2.5em;
            color: #ffffff; /* White color */
        }

        /* Table styling */
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 0 auto 40px auto;
            background-color: #1e1e1e;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        }

        th, td {
            padding: 15px;
            text-align: center;
            border-bottom: 1px solid #444444;
        }

        th {
            background-color: #2a2a2a;
            font-size: 1em;
            letter-spacing: 0.5px;
        }

        tr:nth-child(even) {
            background-color: #2a2a2a;
        }

        tr:hover {
            background-color: #333333;
            transform: scale(1.02);
            transition: transform 0.2s ease-in-out;
        }

        /* Button styling */
        .button {
            background-color: #444444;
            color: #ffffff;
            padding: 8px 16px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-weight: 600;
            transition: background-color 0.3s ease, transform 0.2s ease;
        }

        .button:hover {
            background-color: #555555;
            transform: translateY(-2px);
        }

        /* Responsive Design */
        @media (max-width: 768px) {
            .navbar .nav-links {
                display: none;
                flex-direction: column;
                width: 100%;
                background-color: #1a1a1a;
                position: absolute;
                top: 60px;
                left: 0;
                padding: 10px 0;
            }

            .navbar .nav-links.active {
                display: flex;
            }

            .navbar .nav-link {
                margin: 10px 0;
            }

            .navbar-toggler {
                display: block; /* Show on small screens */
            }
        }
    </style>
</head>
<body>
<nav class="navbar navbar-expand-md navbar-dark">
    <div class="container">
        <a class="navbar-brand" href="home.php"><b>TaxEase</b></a>
        <button class="navbar-toggler border-0" type="button" id="navbar-toggler">
            <span class="navbar-toggler-icon"></span>
        </button>

        <div class="collapse navbar-collapse nav-links" id="navigation">
            <ul class="navbar-nav ml-auto d-flex">
                <li class="nav-item">
                    <a class="nav-link" href="home.php">Home</a>
                </li>
                <?php if ($is_admin): ?>
                    <li class="nav-item">
                        <a class="nav-link" href="add.php">Update FAQ</a>
                    </li>
                <?php endif; ?>
            </ul>
        </div>
    </div>
</nav>

<h1>Late Payments!</h1>

<table>
    <thead>
        <tr>
            <th>User ID</th>
            <th>First Name</th>
            <th>Last Name</th>
            <th>Income Tax Paid</th>
            <th>Land Tax Paid</th>
            <th>Vehicle Tax Paid</th>
            <th>Payment Status</th>
        </tr>
    </thead>
    <tbody>
    <?php
    // Display results in a table
    if ($result->num_rows > 0) {
        while ($row = $result->fetch_assoc()) {
            // Format dates for better readability
            $income_tax_paiddate = $row['income_tax_paiddate'] ? date("F j, Y", strtotime($row['income_tax_paiddate'])) : 'Not Paid';
            $land_tax_paiddate = $row['land_tax_paiddate'] ? date("F j, Y", strtotime($row['land_tax_paiddate'])) : 'Not Paid';
            $vehicle_tax_paiddate = $row['vehicle_tax_paiddate'] ? date("F j, Y", strtotime($row['vehicle_tax_paiddate'])) : 'Not Paid';

            echo "<tr>
                    <td>{$row['u_id']}</td>
                    <td>{$row['first_name']}</td>
                    <td>{$row['last_name']}</td>
                    <td>{$income_tax_paiddate}</td>
                    <td>{$land_tax_paiddate}</td>
                    <td>{$vehicle_tax_paiddate}</td>
                    <td>{$row['payment_status']}</td>
                  </tr>";
        }
    } else {
        echo "<tr><td colspan='7'>No records found.</td></tr>";
    }
    ?>
    </tbody>
</table>

<script>
    // Toggle Navbar on Mobile
    const toggler = document.getElementById('navbar-toggler');
    const navLinks = document.getElementById('navigation');

    toggler.addEventListener('click', () => {
        navLinks.classList.toggle('active');
        toggler.classList.toggle('active');
    });
</script>
</body>
</html>
