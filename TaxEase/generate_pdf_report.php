<?php

session_start();
require('./fpdf/fpdf.php');

$host = "localhost";
$user = "root";
$password = ""; 
$dbname = "tax"; 

$conn = new mysqli($host, $user, $password, $dbname);

if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}

if (!isset($_SESSION['user_id'])) {
    die("User not logged in");
}

$user_id = $_SESSION['user_id'];

if (isset($_POST['year'])) {
    $year = intval($_POST['year']); // Ensure $year is an integer to prevent SQL injection
    
    $query = "SELECT 
                YEAR(paying_date) AS payment_year,
                paying_amount,
                paying_gateway,
                paying_date
            FROM payment_incometax
            WHERE YEAR(paying_date) = $year AND user_id = $user_id
            
            UNION ALL

            SELECT 
                YEAR(paying_date) AS payment_year,
                paying_amount,
                paying_gateway,
                paying_date
            FROM payment_land
            WHERE YEAR(paying_date) = $year AND user_id = $user_id

            UNION ALL

            SELECT 
                YEAR(paying_date) AS payment_year,
                paying_amount,
                paying_gateway,
                paying_date
            FROM payment_vehicle
            WHERE YEAR(paying_date) = $year AND user_id = $user_id

            ORDER BY paying_date DESC;";

    $result = $conn->query($query);

    
    if ($result->num_rows > 0) {
        $pdf = new FPDF();
        $pdf->AddPage();
        $pdf->SetFont('Arial', 'B', 16); 
        $pdf->Cell(0, 10, "Yearly Tax Payment Report for $year", 1, 1, 'C');
        $pdf->Ln(10);
        $pdf->SetFont('Arial', 'B', 12);
        $pdf->SetFillColor(200, 200, 200); // Light gray background for headers
        $pdf->Cell(50, 10, "Paying Amount", 1, 0, 'C', true);
        $pdf->Cell(50, 10, "Paying Date", 1, 0, 'C', true);
        $pdf->Cell(50, 10, "Paying Gateway", 1, 1, 'C', true);

        
        $pdf->SetFont('Arial', '', 12);
        while ($row = $result->fetch_assoc()) {
            $pdf->Cell(50, 10, "$" . number_format($row['paying_amount'], 2), 1, 0, 'C');
            $pdf->Cell(50, 10, date("F j, Y", strtotime($row['paying_date'])), 1, 0, 'C');
            $pdf->Cell(50, 10, ucfirst($row['paying_gateway']), 1, 1, 'C');
        }

        
        $pdf->Output('D', "Yearly_Tax_Report_$year.pdf");
    } else {
        // If no records found, set a flag to trigger JavaScript alert
        $no_records = true;
    }
} 

$conn->close();
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Yearly Report - TaxEase</title>
    <!-- Google Fonts -->
    <link href="https://fonts.googleapis.com/css?family=Open+Sans:400,600,700&display=swap" rel="stylesheet">
    <!-- Bootstrap CSS (Optional for additional styling) -->
    <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.0/css/bootstrap.min.css">
    <style>
        /* Reset some default browser styles */
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        /* Body styling */
        body {
            font-family: 'Open Sans', sans-serif;
            background-color: #f4f4f4; /* Light gray background */
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            padding: 20px;
        }

        /* Container for the form */
        .form-container {
            background-color: #ffffff; /* White background */
            border-radius: 15px;
            box-shadow: 0 8px 25px rgba(0, 0, 0, 0.1);
            padding: 40px;
            width: 100%;
            max-width: 500px;
            text-align: center;
            transition: transform 0.3s ease, box-shadow 0.3s ease;
        }

        .form-container:hover {
            transform: translateY(-5px);
            box-shadow: 0 12px 30px rgba(0, 0, 0, 0.2);
        }

        /* Form header */
        .form-container h2 {
            color: #333333;
            margin-bottom: 30px;
            font-size: 28px;
            font-weight: 700;
        }

        /* Label styling */
        .form-container label {
            display: block;
            text-align: left;
            margin-bottom: 8px;
            color: #333333;
            font-weight: 600;
            font-size: 16px;
        }

        /* Select styling */
        .form-container select {
            width: 100%;
            padding: 12px 15px;
            border: 1px solid #cccccc;
            border-radius: 5px;
            font-size: 16px;
            margin-bottom: 25px;
            background-color: #ffffff;
            color: #333333;
            transition: border-color 0.3s ease, box-shadow 0.3s ease;
        }

        .form-container select:focus {
            border-color: #000000; /* Black border on focus */
            box-shadow: 0 0 5px rgba(0, 0, 0, 0.2);
            outline: none;
        }

        /* Button styling */
        .form-container button {
            background-color: #000000; /* Black background */
            color: white; /* White text */
            border: none;
            padding: 12px 20px;
            font-size: 16px;
            border-radius: 5px;
            cursor: pointer;
            width: 100%;
            transition: background-color 0.3s ease, transform 0.2s ease;
            font-weight: 600;
        }

        /* Button hover effect */
        .form-container button:hover {
            background-color: #333333; /* Darker black on hover */
            transform: translateY(-2px);
        }

        /* Home button styling */
        .home-button {
            display: inline-block;
            margin-top: 20px;
            background-color: #000000; /* Black background */
            color: white; /* White text */
            padding: 10px 20px;
            text-decoration: none;
            font-size: 14px;
            border-radius: 5px;
            transition: background-color 0.3s ease;
            font-weight: 600;
        }

        .home-button:hover {
            background-color: #333333; /* Darker black on hover */
        }

        /* Form responsiveness for mobile devices */
        @media (max-width: 576px) {
            .form-container {
                padding: 30px 20px;
            }

            .form-container h2 {
                font-size: 24px;
            }

            .form-container button,
            .home-button {
                padding: 10px 15px;
                font-size: 14px;
            }
        }
    </style>
    <?php
    // If no records found, output JavaScript to show alert
    if (isset($no_records) && $no_records === true) {
        echo "<script>alert('No records found for the selected year.');</script>";
    }
    ?>
</head>
<body>

    <div class="form-container">
        <h2>Select Year to Generate Report</h2>
        <form method="POST" action="generate_pdf_report.php">
            <label for="year">Select Year:</label>
            <select name="year" id="year" required>
                <?php
                $currentYear = date("Y");
                for ($i = $currentYear; $i >= $currentYear - 10; $i--) {
                    // Retain the selected year after form submission
                    $selected = (isset($year) && $year == $i) ? 'selected' : '';
                    echo "<option value=\"$i\" $selected>$i</option>";
                }
                ?>
            </select>
            <button type="submit">Generate Report</button>
        </form>
        <a href="dashboard2.php" class="home-button">Back to Home</a>
    </div>

    <!-- Bootstrap JS and dependencies (Optional for additional interactivity) -->
    <script src="https://code.jquery.com/jquery-3.5.1.slim.min.js" integrity="sha384-DfXdOtmVgAwfGJN1/vVQx7Zplm21GgI1XdtIiq1iIfdN7ZpkaZy/xxO9uJp9IGW4" crossorigin="anonymous"></script>
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@4.5.0/dist/js/bootstrap.bundle.min.js" integrity="sha384-1CmrxMRARb6aLqgBO7yyAxTOQE2AKb9GfXnE5C2VJ2M1dfGvJoG7iQVplKdfwF8N" crossorigin="anonymous"></script>
</body>
</html>
