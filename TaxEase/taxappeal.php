<?php
include('connect.php'); 
session_start();
if (!isset($_SESSION['user_id'])) {
    header("Location: login.php");
    exit();
}

$user_id = $_SESSION['user_id'];
$query = "SELECT first_name, last_name, nid, etin, user_id FROM registered WHERE user_id = '$user_id'";
$result = mysqli_query($conn, $query);

if ($result && mysqli_num_rows($result) > 0) {
    $user_data = mysqli_fetch_assoc($result);
} else {
    echo "<script>alert('User data not found.');</script>";
}

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    //$first_name = $_POST['first_name'];
    //$last_name = $_POST['last_name'];
    $user_id = $_POST['user_id'];
    $category_id = $_POST['category_id'];
    $etin = $_POST['etin'];
    $appeal_date = $_POST['appeal_date'];
    $appeal_text = $_POST['appeal_text'];

    $query = "INSERT INTO appeal 
    (user_id, category_id, etin, appeal_text, appeal_date) 
    VALUES 
    ('$user_id', '$category_id', '$etin', '$appeal_text', '$appeal_date')";

    if (mysqli_query($conn, $query)) {
        echo "<script>alert('successful!');</script>";
        header("Location: dashboard2.php");
    } else {
        echo "<script>alert('Error: " . mysqli_error($conn) . "');</script>";
    }
}
?>

<style type="text/css">
body {
    background-image: url(images/app.png) !important;
    background-repeat: no-repeat !important;
    background-attachment: fixed !important;
    background-position: center !important;
    background-size: cover !important;
}

.form-control:focus {
    color: #ffffff !important;
    background-color: #1d1d1d !important;
    border-color: #000000 !important;
    outline: 0;
    box-shadow: 0 0 0 0rem rgb(0, 0, 0) !important;
}

.btn-primary {
    background-color: rgba(255, 255, 255, 0.7) !important; /* Slightly faded white */
    color: #000000 !important; /* Black font color */
    border: 2px solid #1d1d1d !important;
    padding: 10px 20px !important;
    margin-top: 40px !important;
    font-size: 24px !important;
    font-weight: bold !important;
    border-radius: 20px !important;
}

.btn-primary1 {
    background-color: #000000 !important;
    padding: 6px 12px !important;
    color: #eee !important;
    font-size: 1rem !important;
    font-weight: bold !important;
    border-radius: 20px !important;
}

.btn-secondary:focus {
    box-shadow: 0 0 0 0rem rgba(191, 223, 252, 0.5) !important;
}

.close:focus {
    box-shadow: 0 0 0 0rem rgba(159, 209, 255, 0.5) !important;
}

.btn-secondary.disabled {
    background-color: #000000 !important;
}

.btn-secondary {
    background-color: #000000 !important;
    padding: 6px 12px !important;
    color: #eee !important;
    font-size: 1rem !important;
    font-weight: bold !important;
    border-radius: 20px !important;
}

.mt-200 {
    margin-top: 300px;
}

.sw-theme-default > ul.step-anchor > li.active > a {
    color: #000000 !important;
}

.back-home-button {
    position: absolute;
    top: 20px;
    right: 20px;
    background-color: black;
    color: white;
    border: none;
    padding: 10px 20px;
    font-size: 16px;
    border-radius: 4px;
    cursor: pointer;
    transition: background-color 0.3s ease;
}

.back-home-button:hover {
    background-color: #333333;
}
</style>

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Step Wizard</title>
    <!-- Smart Wizard CSS -->
    <link href="https://cdn.jsdelivr.net/gh/bbbootstrap/libraries@main/smart_wizard.min.css" rel="stylesheet" type="text/css" />
    <link href="https://cdn.jsdelivr.net/gh/bbbootstrap/libraries@main/smart_wizard_theme_arrows.min.css" rel="stylesheet" type="text/css" />
    <!-- Bootstrap CSS -->
    <link href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css" rel="stylesheet" type="text/css" />
</head>
<body>

<div class="container">
    <button class="back-home-button" onclick="window.location.href='dashboard2.php';">Back to Home</button>
    <div class="row d-flex justify-content-center mt-200">
        <button type="button" class="btn btn-primary" data-toggle="modal" data-target="#exampleModal">
            APPEAL FOR YOUR TAX
        </button>
    </div>

    <!-- Modal -->
    <div class="modal fade" id="exampleModal" tabindex="-1" role="dialog" aria-labelledby="exampleModalLabel" aria-hidden="true">
        <div class="modal-dialog modal-lg modal-dialog-centered" role="document">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="exampleModalLabel">Fill in the following requirements</h5>
                    <button type="button" class="close" data-dismiss="modal" aria-label="Close">
                        <span aria-hidden="true">&times;</span>
                    </button>
                </div>
                <div class="modal-body">
                    <!-- Added form element with POST method -->
                    <form method="POST">
                        <div id="smartwizard">
                            <ul>
                                <li><a href="#step-1">Step 1<br /><small>Account Info</small></a></li>
                                <li><a href="#step-2">Step 2<br /><small>Personal Info</small></a></li>
                                <li><a href="#step-3">Step 3<br /><small>Payment Info</small></a></li>
                                <li><a href="#step-4">Step 4<br /><small>Confirm Details</small></a></li>
                            </ul>
                            <div class="mt-4">
                                <div id="step-1">
                                    <div class="row">
                                        <div class="col-md-6">
                                            <input type="text" name="first_name" class="form-control" value="<?php echo isset($user_data['first_name']) ? $user_data['first_name'] : ''; ?>" placeholder="First Name" required>
                                        </div>
                                        <div class="col-md-6">
                                            <input type="text" name="last_name" class="form-control" value="<?php echo isset($user_data['last_name']) ? $user_data['last_name'] : ''; ?>" placeholder="Last Name" required>
                                        </div>
                                    </div>
                                </div>
                                <div id="step-2">
                                    <div class="row">
                                        <div class="col-md-6">
                                            <input type="number" name="user_id" class="form-control" value="<?php echo isset($user_data['user_id']) ? $user_data['user_id'] : ''; ?>" placeholder="User ID" required>
                                        </div>
                                        <div class="col-md-6">
                                            <input type="text" name="category_id" class="form-control" placeholder="Category ID" required>
                                        </div>
                                    </div>
                                </div>
                                <div id="step-3">
                                    <div class="row">
                                        <div class="col-md-6">
                                            <input type="text" name="etin" class="form-control" value="<?php echo isset($user_data['etin']) ? $user_data['etin'] : ''; ?>" placeholder="E-TIN Number" required>
                                        </div>
                                        <div class="col-md-6">
                                            <input type="date" name="appeal_date" class="form-control" placeholder="Appeal Date" required>
                                        </div>
                                    </div>
                                </div>
                                <div id="step-4">
                                    <div class="row">
                                        <div class="col-md-12">
                                            <textarea rows="4" cols="50" name="appeal_text" class="form-control" placeholder="Submit your reason for appeal" required></textarea>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-dismiss="modal">Close</button>
                            <!-- Changed button type to submit to trigger form submission -->
                            <button type="submit" name="submit" class="btn btn-primary1">Submit</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- Scripts -->
<script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@popperjs/core@2.11.6/dist/umd/popper.min.js"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/js/bootstrap.min.js"></script>
<script src="https://cdn.jsdelivr.net/gh/bbbootstrap/libraries@main/jquery.smartWizard.min.js"></script>
<script>
    $(document).ready(function() {
        $('#smartwizard').smartWizard();
    });
</script>

</body>
</html>
