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

$user_id = $_SESSION['user_id'];
$query1 = "SELECT incomestatus, email FROM registered WHERE user_id = ?";
$stmt = $conn->prepare($query1);
$stmt->bind_param("i", $user_id);
$stmt->execute();
$result = $stmt->get_result();

// Handle form submissions for updating appeal status
if ($_SERVER["REQUEST_METHOD"] == "POST") {
    // Get appeal ID and button value
    $appeal_id = $_POST['appeal_id'];
    $button_value = $_POST['status'];
    
    // Validate the input
    if (in_array($button_value, ['accepted', 'rejected'])) {
        // Update the statuss in the appeal table
        $update_query = "UPDATE appeal SET statuss = ? WHERE appeal_id = ?";
        $stmt = $conn->prepare($update_query);
        $stmt->bind_param("si", $button_value, $appeal_id);
        if ($stmt->execute()) {
            echo "<script>alert('Status updated successfully!');</script>";
        } else {
            echo "<script>alert('Error updating status: " . $stmt->error . "');</script>";
        }
    }
}

// Query to fetch appeal history
$query = "SELECT appeal_id, appeal_date, appeal_text, statuss, user_id FROM appeal";
$result = $conn->query($query);
?>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <link rel="apple-touch-icon" sizes="76x76" href="./assets/img/apple-icon.png">
    <link rel="icon" type="image/png" href="./assets/img/favicon.png">
    <title>TaxEase</title>
    <link href="https://fonts.googleapis.com/css?family=Open+Sans:300,400,600,700" rel="stylesheet" />
    <link href="./assets/css/nucleo-icons.css" rel="stylesheet" />
    <link href="./assets/css/nucleo-svg.css" rel="stylesheet" />
    <script src="https://kit.fontawesome.com/42d5adcbca.js" crossorigin="anonymous"></script>
    <link id="pagestyle" href="./assets/css/argon-dashboard.css?v=2.0.4" rel="stylesheet" />
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body {
            background-color: #0d0d0d;
            color: #f5f5f5;
            font-family: 'Open Sans', sans-serif;
            margin: 0;
            padding: 0;
        }

        .card {
            background-color: #1c1c1c;
            border-radius: 12px;
            border: none;
            margin: 20px auto;
            max-width: 1200px;
            padding: 20px;
            box-shadow: 0px 4px 8px rgba(0, 0, 0, 0.2);
        }

        h6 {
            font-size: 18px;
            font-weight: 700;
            margin-bottom: 10px;
            color: #ffffff;
            text-align: center;
        }

        .table {
            width: 100%;
            color: #ffffff;
            margin-top: 20px;
            border-collapse: collapse;
        }

        th, td {
            padding: 12px;
            text-align: center;
            border-bottom: 1px solid #444;
        }

        th {
            background-color: #2a2a2a;
            color: #ffffff;
            font-size: 16px;
        }

        td {
            background-color: #1e1e1e;
        }

        tr:hover td {
            background-color: #333;
        }

        .btn {
            border: none;
            padding: 10px 20px;
            font-size: 14px;
            border-radius: 4px;
            cursor: pointer;
            transition: background-color 0.3s ease;
        }

        .btn-accept {
            background-color: #000000;
            color: #ffffff;
        }

        .btn-accept:hover {
            background-color: #404040;
        }

        .btn-reject {
            background-color: #f44336;
            color: #ffffff;
        }

        .btn-reject:hover {
            background-color: #d32f2f;
        }

        .status-accepted {
            color: #4caf50;
            font-weight: bold;
        }

        .status-rejected {
            color: #f44336;
            font-weight: bold;
        }

        .status-pending {
            color: #9e9e9e;
            font-weight: bold;
        }
    </style>
</head>
<body>
<div class="card">
    <h6>Tax Appeal History</h6>
    <div class="table-responsive">
        <table class="table">
            <thead>
                <tr>
                    <th>Date</th>
                    <th>User ID</th>
                    <th>Appeal Text</th>
                    <th>Status</th>
                    <th>Actions</th>
                </tr>
            </thead>
            <tbody>
            <?php
            // Display appeal history
            if ($result->num_rows > 0) {
                while ($row = $result->fetch_assoc()) {
                    echo '<tr>';
                    echo '<td>' . htmlspecialchars($row['appeal_date']) . '</td>';
                    echo '<td>' . htmlspecialchars($row['user_id']) . '</td>';
                    echo '<td>' . htmlspecialchars($row['appeal_text']) . '</td>';
                    echo '<td class="' . 
                        ($row['statuss'] == 'accepted' ? 'status-accepted' : ($row['statuss'] == 'rejected' ? 'status-rejected' : 'status-pending')) . 
                        '">' . htmlspecialchars($row['statuss']) . '</td>';
                    echo '<td>';
                    echo '<form method="POST">';
                    echo '<input type="hidden" name="appeal_id" value="' . htmlspecialchars($row['appeal_id']) . '">';
                    echo '<button type="submit" name="status" value="accepted" class="btn btn-accept">Accept</button>';
                    echo '<button type="submit" name="status" value="rejected" class="btn btn-reject">Reject</button>';
                    echo '</form>';
                    echo '</td>';
                    echo '</tr>';
                }
            } else {
                echo '<tr><td colspan="5">No appeal history found.</td></tr>';
            }
            ?>
            </tbody>
        </table>
    </div>
</div>
</body>
</html>
